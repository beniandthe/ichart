import XCTest
@testable import iChart

final class ChordSymbolParserTests: XCTestCase {
    private let chromaticSpellings = [
        "C",
        "C#",
        "Cb",
        "D",
        "D#",
        "Db",
        "E",
        "E#",
        "Eb",
        "F",
        "F#",
        "Fb",
        "G",
        "G#",
        "Gb",
        "A",
        "A#",
        "Ab",
        "B",
        "B#",
        "Bb"
    ]

    func testChordRecognitionCompendiumMatchesCompatibilityWrapper() {
        for spelling in chromaticSpellings + chromaticSpellings.map({ "\($0)-" }) {
            XCTAssertEqual(
                ChordRecognitionCompendium.match(spelling)?.displayText,
                BasicMajorChordCompendium.match(spelling)?.displayText
            )
        }
    }

    func testBasicMajorChordCompendiumRecognizesChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let match = try XCTUnwrap(
                BasicMajorChordCompendium.match(spelling),
                "Expected compendium to recognize \(spelling)"
            )
            XCTAssertEqual(match.displayText, spelling)
            XCTAssertTrue(match.symbol.quality.isEmpty)
        }
    }

    func testBasicMajorChordCompendiumNormalizesHandwritingOcrVariants() {
        let expectations = [
            " d flat ": "Db",
            "D FLAT": "Db",
            "F sharp": "F#",
            "c SHARP": "C#",
            "B♭": "Bb",
            "C♭": "Cb",
            "F♯": "F#",
            "A＃": "A#",
            "B flat minor": "Bb-",
            "G sharp min": "G#-",
            "E−": "E-"
        ]

        for (input, expected) in expectations {
            XCTAssertEqual(BasicMajorChordCompendium.match(input)?.displayText, expected, input)
        }

        XCTAssertEqual(BasicMajorChordCompendium.match("Cm7")?.displayText, "C-7")
    }

    func testBasicMajorChordCompendiumRecognizesMinorAliases() {
        for spelling in chromaticSpellings {
            for suffix in ["-", "m", "min", " minor"] {
                XCTAssertEqual(
                    BasicMajorChordCompendium.match("\(spelling)\(suffix)")?.displayText,
                    "\(spelling)-",
                    "\(spelling)\(suffix)"
                )
            }
        }

        XCTAssertEqual(BasicMajorChordCompendium.match("B♭min")?.displayText, "Bb-")
        XCTAssertEqual(BasicMajorChordCompendium.match("F sharp m")?.displayText, "F#-")
    }

    func testChordRecognitionCompendiumRecognizesDominantSeventhAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let expectedDisplayText = "\(spelling)7"

            XCTAssertEqual(
                ChordRecognitionCompendium.match(expectedDisplayText)?.displayText,
                expectedDisplayText,
                expectedDisplayText
            )

            let symbol = try ChordSymbolParser.parse(expectedDisplayText)

            XCTAssertEqual(symbol.quality, "", expectedDisplayText)
            XCTAssertEqual(symbol.extensions, ["7"], expectedDisplayText)
            XCTAssertEqual(symbol.displayText, expectedDisplayText)
        }
    }

    func testChordRecognitionCompendiumRecognizesNonAlteredSixthAndDominantExtensionsAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            for extensionText in ["6", "9", "11", "13"] {
                let expectedDisplayText = "\(spelling)\(extensionText)"

                XCTAssertEqual(
                    ChordRecognitionCompendium.match(expectedDisplayText)?.displayText,
                    expectedDisplayText,
                    expectedDisplayText
                )

                let symbol = try ChordSymbolParser.parse(expectedDisplayText)

                XCTAssertEqual(symbol.quality, "", expectedDisplayText)
                XCTAssertEqual(symbol.extensions, [extensionText], expectedDisplayText)
                XCTAssertEqual(symbol.alterations, [], expectedDisplayText)
                XCTAssertEqual(symbol.displayText, expectedDisplayText)
            }
        }
    }

    func testChordRecognitionCompendiumRecognizesMinorSixthAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let expectedDisplayText = "\(spelling)m6"

            for qualityAlias in ["m6", "m 6", "min6", "min 6", "minor6", " minor6", " minor 6"] {
                let input = "\(spelling)\(qualityAlias)"

                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    expectedDisplayText,
                    input
                )

                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "-", input)
                XCTAssertEqual(symbol.extensions, ["6"], input)
                XCTAssertEqual(symbol.alterations, [], input)
                XCTAssertEqual(symbol.displayText, expectedDisplayText, input)
            }
        }
    }

    func testChordRecognitionCompendiumRecognizesMinorMajorSeventhAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let expectedDisplayText = "\(spelling)-△7"

            for qualityAlias in ["-△7", "-Δ7", "-∆7", "m△7", "m △7", "min△7", "min △7", "minor△7", " minor△7", " minor △7"] {
                let input = "\(spelling)\(qualityAlias)"

                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    expectedDisplayText,
                    input
                )

                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "-△", input)
                XCTAssertEqual(symbol.extensions, ["7"], input)
                XCTAssertEqual(symbol.alterations, [], input)
                XCTAssertEqual(symbol.displayText, expectedDisplayText, input)
            }
        }
    }

    func testChordRecognitionCompendiumRecognizesAugmentedAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let expectedDisplayText = "\(spelling)+"

            for qualityAlias in ["+", "aug", "augmented", " augmented"] {
                let input = "\(spelling)\(qualityAlias)"

                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    expectedDisplayText,
                    input
                )

                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "+", input)
                XCTAssertEqual(symbol.extensions, [], input)
                XCTAssertEqual(symbol.alterations, [], input)
                XCTAssertEqual(symbol.displayText, expectedDisplayText, input)
            }
        }
    }

    func testChordRecognitionCompendiumRecognizesPureAlteredAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let expectedDisplayText = "\(spelling)7alt"

            for qualityAlias in ["alt", " alt", "7alt", " 7alt", "7 alt", " 7 alt", "altered", " altered", "7altered", " 7altered"] {
                let input = "\(spelling)\(qualityAlias)"

                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    expectedDisplayText,
                    input
                )

                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "alt", input)
                XCTAssertEqual(symbol.extensions, ["7"], input)
                XCTAssertEqual(symbol.alterations, [], input)
                XCTAssertEqual(symbol.displayText, expectedDisplayText, input)
            }
        }
    }

    func testChordRecognitionCompendiumRecognizesPlainSuspendedAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let expectedDisplayText = "\(spelling)sus"

            for qualityAlias in ["sus", " sus", "suspended", " suspended"] {
                let input = "\(spelling)\(qualityAlias)"

                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    expectedDisplayText,
                    input
                )

                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "sus", input)
                XCTAssertEqual(symbol.extensions, [], input)
                XCTAssertEqual(symbol.alterations, [], input)
                XCTAssertEqual(symbol.displayText, expectedDisplayText, input)
            }
        }
    }

    func testChordRecognitionCompendiumRecognizesSuspendedFourthAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let expectedDisplayText = "\(spelling)sus4"

            for qualityAlias in ["sus4", " sus4", "sus 4", " sus 4", "suspended4", " suspended4", "suspended 4", " suspended 4"] {
                let input = "\(spelling)\(qualityAlias)"

                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    expectedDisplayText,
                    input
                )

                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "sus", input)
                XCTAssertEqual(symbol.extensions, ["4"], input)
                XCTAssertEqual(symbol.alterations, [], input)
                XCTAssertEqual(symbol.displayText, expectedDisplayText, input)
            }
        }
    }

    func testChordRecognitionCompendiumRecognizesDominantSuspendedAcrossChromaticSpellings() throws {
        for spelling in chromaticSpellings {
            let expectedDisplayText = "\(spelling)7sus"

            for qualityAlias in ["7sus", " 7sus", "7 sus", " 7 sus", "7suspended", " 7suspended", "7 suspended", " 7 suspended"] {
                let input = "\(spelling)\(qualityAlias)"

                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    expectedDisplayText,
                    input
                )

                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "sus", input)
                XCTAssertEqual(symbol.extensions, ["7"], input)
                XCTAssertEqual(symbol.alterations, [], input)
                XCTAssertEqual(symbol.displayText, expectedDisplayText, input)
            }
        }
    }

    func testBasicMajorChordCompendiumRejectsMajorSuffixAliases() {
        for spelling in chromaticSpellings {
            XCTAssertNil(BasicMajorChordCompendium.match("\(spelling)M"), spelling)
            XCTAssertNil(BasicMajorChordCompendium.match("\(spelling)maj"), spelling)
            XCTAssertNil(BasicMajorChordCompendium.match("\(spelling) major"), spelling)
        }
    }

    func testChordRecognitionCompendiumCandidateOrderingSkipsInvalidCandidates() {
        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: ["8b", "Bb"])?.displayText,
            "Bb"
        )
        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: ["Cmaj", "C"])?.displayText,
            "C"
        )
        XCTAssertNil(
            ChordRecognitionCompendium.match(candidates: ["8b", "H", "Cmaj7"])
        )
        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: ["C-△", "C-7"])?.displayText,
            "C-7"
        )
    }

    func testChordRecognitionCompendiumFallsBackToParserForSupportedExtensions() {
        XCTAssertEqual(ChordRecognitionCompendium.match("Cm7")?.displayText, "C-7")
        XCTAssertEqual(ChordRecognitionCompendium.match("Db7b9/D")?.displayText, "Db7(b9)/D")
        XCTAssertEqual(ChordRecognitionCompendium.match("Db7(b9)/D")?.displayText, "Db7(b9)/D")
        XCTAssertEqual(ChordRecognitionCompendium.match("Db7#9/D")?.displayText, "Db7(#9)/D")
        XCTAssertEqual(ChordRecognitionCompendium.match("Db7(#9)/D")?.displayText, "Db7(#9)/D")
        XCTAssertEqual(ChordRecognitionCompendium.match("G/B")?.displayText, "G/B")
        XCTAssertEqual(ChordRecognitionCompendium.match("C△")?.displayText, "C△")
        XCTAssertEqual(ChordRecognitionCompendium.match("C△9")?.displayText, "C△9")
        XCTAssertEqual(ChordRecognitionCompendium.match("Csus4")?.displayText, "Csus4")
        XCTAssertEqual(ChordRecognitionCompendium.match("C7sus")?.displayText, "C7sus")
        XCTAssertNil(ChordRecognitionCompendium.match("CM7"))
        XCTAssertNil(ChordRecognitionCompendium.match("Cmaj7"))
    }

    func testZeroTranspositionPreservesWrittenEnharmonicSpellings() throws {
        let spellings = ["Cb", "E#", "Fb", "B#"]

        for spelling in spellings {
            let symbol = try XCTUnwrap(BasicMajorChordCompendium.match(spelling)?.symbol)

            XCTAssertEqual(symbol.transposed(by: 0).displayText, spelling)
        }
    }

    func testConcertChordEventViewPreservesWrittenEnharmonicSpellings() throws {
        let symbol = try XCTUnwrap(BasicMajorChordCompendium.match("E#")?.symbol)
        let event = ChordEvent(
            id: UUID(),
            symbol: symbol,
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .quarter,
            rhythmPlacement: .inline,
            tieOut: false,
            hitStyle: .none,
            rawInput: "E#"
        )

        XCTAssertEqual(event.transposed(for: TranspositionView.concert).symbol.displayText, "E#")
    }

    func testParsesChordWithExtensionAlterationAndSlashBass() throws {
        let symbol = try ChordSymbolParser.parse("Bb7(b9)/D")

        XCTAssertEqual(symbol.root, .b)
        XCTAssertEqual(symbol.accidental, .flat)
        XCTAssertEqual(symbol.quality, "")
        XCTAssertEqual(symbol.extensions, ["7"])
        XCTAssertEqual(symbol.alterations, ["b9"])
        XCTAssertEqual(symbol.slashBass, "D")
        XCTAssertEqual(symbol.displayText, "Bb7(b9)/D")

        let legacySymbol = try ChordSymbolParser.parse("Bb7b9/D")
        XCTAssertEqual(legacySymbol.displayText, "Bb7(b9)/D")
    }

    func testParsesAlteredDominantExtensionsAsParenthesizedDisplayText() throws {
        let symbol = try ChordSymbolParser.parse("C7(b9)(#5)")
        let flatFiveSymbol = try ChordSymbolParser.parse("C7b5")
        let sharpFiveSymbol = try ChordSymbolParser.parse("C7#5")
        let sharpNineSymbol = try ChordSymbolParser.parse("C7#9")
        let sharpElevenSymbol = try ChordSymbolParser.parse("C7#11")

        XCTAssertEqual(symbol.extensions, ["7"])
        XCTAssertEqual(symbol.alterations, ["b9", "#5"])
        XCTAssertEqual(symbol.displayText, "C7(b9)(#5)")
        XCTAssertEqual(try ChordSymbolParser.parse("C7b9#5").displayText, "C7(b9)(#5)")
        XCTAssertEqual(flatFiveSymbol.extensions, ["7"])
        XCTAssertEqual(flatFiveSymbol.alterations, ["b5"])
        XCTAssertEqual(flatFiveSymbol.displayText, "C7(b5)")
        XCTAssertEqual(try ChordSymbolParser.parse("C7(b5)").displayText, "C7(b5)")
        XCTAssertEqual(sharpFiveSymbol.extensions, ["7"])
        XCTAssertEqual(sharpFiveSymbol.alterations, ["#5"])
        XCTAssertEqual(sharpFiveSymbol.displayText, "C7(#5)")
        XCTAssertEqual(try ChordSymbolParser.parse("C7(#5)").displayText, "C7(#5)")
        XCTAssertEqual(sharpNineSymbol.extensions, ["7"])
        XCTAssertEqual(sharpNineSymbol.alterations, ["#9"])
        XCTAssertEqual(sharpNineSymbol.displayText, "C7(#9)")
        XCTAssertEqual(try ChordSymbolParser.parse("C7(#9)").displayText, "C7(#9)")
        XCTAssertEqual(sharpElevenSymbol.extensions, ["7"])
        XCTAssertEqual(sharpElevenSymbol.alterations, ["#11"])
        XCTAssertEqual(sharpElevenSymbol.displayText, "C7(#11)")
        XCTAssertEqual(try ChordSymbolParser.parse("C7(#11)").displayText, "C7(#11)")
    }

    func testParsesSlashBassWithoutDescriptorBeforeSlash() throws {
        let symbol = try ChordSymbolParser.parse("G/B")

        XCTAssertEqual(symbol.root, .g)
        XCTAssertEqual(symbol.quality, "")
        XCTAssertEqual(symbol.slashBass, "B")
        XCTAssertEqual(symbol.displayText, "G/B")
    }

    func testRejectsSlashBassWithTrailingNonPitchCharacters() {
        XCTAssertThrowsError(try ChordSymbolParser.parse("D/F5")) { error in
            XCTAssertEqual(error as? ChordSymbolParseError, .invalidSlashBass)
        }
        XCTAssertThrowsError(try ChordSymbolParser.parse("F#/A5")) { error in
            XCTAssertEqual(error as? ChordSymbolParseError, .invalidSlashBass)
        }
    }

    func testParsesMinorChordAliasesToJazzMinorQuality() throws {
        for spelling in ["C-", "Cm", "Cmin", "Cminor", "C minor"] {
            let symbol = try ChordSymbolParser.parse(spelling)

            XCTAssertEqual(symbol.displayText, "C-", spelling)
        }

        let extendedMinor = try ChordSymbolParser.parse("Dbmin7")

        XCTAssertEqual(extendedMinor.displayText, "Db-7")
    }

    func testParsesMinorSixthNinthEleventhAndThirteenthAliasesToJazzMinorQuality() throws {
        for spelling in chromaticSpellings {
            for extensionText in ["6", "9", "11", "13"] {
                let expectedDisplayText = extensionText == "6"
                    ? "\(spelling)m6"
                    : "\(spelling)-\(extensionText)"

                for qualityAlias in ["-", "m", "min", " minor"] {
                    let input = "\(spelling)\(qualityAlias)\(extensionText)"
                    let symbol = try ChordSymbolParser.parse(input)

                    XCTAssertEqual(symbol.quality, "-", input)
                    XCTAssertEqual(symbol.extensions, [extensionText], input)
                    XCTAssertEqual(symbol.displayText, expectedDisplayText, input)
                    XCTAssertEqual(
                        ChordRecognitionCompendium.match(input)?.displayText,
                        expectedDisplayText,
                        input
                    )
                }
            }
        }
    }

    func testParsesDiminishedAndHalfDiminishedAliasesToJazzSymbols() throws {
        for spelling in chromaticSpellings {
            let diminishedDisplayText = "\(spelling)°"
            let diminishedSeventhDisplayText = "\(spelling)°7"
            let halfDiminishedDisplayText = "\(spelling)ø7"

            for qualityAlias in ["°", "º", "dim", "diminished", " diminished"] {
                let input = "\(spelling)\(qualityAlias)"
                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "°", input)
                XCTAssertEqual(symbol.extensions, [], input)
                XCTAssertEqual(symbol.displayText, diminishedDisplayText, input)
                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    diminishedDisplayText,
                    input
                )
            }

            for qualityAlias in ["°7", "º7", "dim7", "diminished7", " diminished7"] {
                let input = "\(spelling)\(qualityAlias)"
                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "°", input)
                XCTAssertEqual(symbol.extensions, ["7"], input)
                XCTAssertEqual(symbol.displayText, diminishedSeventhDisplayText, input)
                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    diminishedSeventhDisplayText,
                    input
                )
            }

            for qualityAlias in ["ø", "ø7", "Ø", "Ø7", "half-dim7", "half dim7", "halfdim7", "half-diminished7", "half diminished7", "m7b5", "min7b5", "-7b5"] {
                let input = "\(spelling)\(qualityAlias)"
                let symbol = try ChordSymbolParser.parse(input)

                XCTAssertEqual(symbol.quality, "ø", input)
                XCTAssertEqual(symbol.extensions, ["7"], input)
                XCTAssertEqual(symbol.alterations, [], input)
                XCTAssertEqual(symbol.displayText, halfDiminishedDisplayText, input)
                XCTAssertEqual(
                    ChordRecognitionCompendium.match(input)?.displayText,
                    halfDiminishedDisplayText,
                    input
                )
            }
        }
    }

    func testParsesTriangleMajorQualityForExtendedMajorChords() throws {
        let expectations = [
            "C△7": "C△7",
            "CΔ9": "C△9",
            "C∆13": "C△13"
        ]

        for (spelling, expectedDisplayText) in expectations {
            let symbol = try ChordSymbolParser.parse(spelling)

            XCTAssertEqual(symbol.quality, "△", spelling)
            XCTAssertEqual(symbol.displayText, expectedDisplayText, spelling)
        }

        let symbol = ChordSymbol(
            root: .b,
            accidental: .flat,
            quality: "maj",
            extensions: ["7"],
            alterations: [],
            slashBass: nil
        )

        XCTAssertEqual(symbol.displayText, "Bb△7")
    }

    func testParsesMinorMajorSeventhWithDashTriangleQuality() throws {
        let expectations = [
            "C-△7": "C-△7",
            "C-Δ7": "C-△7",
            "Cm△7": "C-△7",
            "Cmin△7": "C-△7",
            "C minor △7": "C-△7",
            "Bb-△7": "Bb-△7",
            "F#-△7": "F#-△7"
        ]

        for (spelling, expectedDisplayText) in expectations {
            let symbol = try ChordSymbolParser.parse(spelling)

            XCTAssertEqual(symbol.quality, "-△", spelling)
            XCTAssertEqual(symbol.extensions, ["7"], spelling)
            XCTAssertEqual(symbol.displayText, expectedDisplayText, spelling)
            XCTAssertEqual(
                ChordRecognitionCompendium.match(spelling)?.displayText,
                expectedDisplayText,
                spelling
            )
        }
    }

    func testParserRejectsUnsupportedMajorSuffixAliases() {
        for spelling in ["CM", "CM7", "Cmaj", "Cmajor", "C major", "Bbmaj7"] {
            XCTAssertThrowsError(try ChordSymbolParser.parse(spelling), spelling)
        }
    }

    func testParserRejectsUnsupportedGlyphNoiseDescriptors() {
        for spelling in ["CC", "CG7", "C△C", "C-△", "C-△9", "C6△7", "C7△", "B6△7", "Bfoo", "E3", "E2", "E8", "C°9", "Cø9", "Cø7b5", "C+b9", "C+(b9)", "Csus7", "C7()", "C7(9)", "Db(b9)", "Db(b9)(b9)", "Db7(b9)(b9)", "Db7b9b9"] {
            XCTAssertThrowsError(try ChordSymbolParser.parse(spelling), spelling)
            XCTAssertNil(ChordRecognitionCompendium.match(spelling), spelling)
        }
    }

    func testParserRejectsUnsupportedNumericNoiseButKeepsSupportedExtensions() {
        for spelling in ["E3", "E2", "E4", "E5", "E8", "E10", "Eb3"] {
            XCTAssertThrowsError(try ChordSymbolParser.parse(spelling), spelling)
            XCTAssertNil(ChordRecognitionCompendium.match(spelling), spelling)
        }

        for spelling in ["E6", "E7", "E9", "E11", "E13", "Db7b9", "Db7(b9)", "Db7#9", "Db7(#9)"] {
            XCTAssertNoThrow(try ChordSymbolParser.parse(spelling), spelling)
            XCTAssertNotNil(ChordRecognitionCompendium.match(spelling), spelling)
        }
    }

    func testChordRecognitionCompendiumFiltersUserFacingSuggestions() {
        XCTAssertEqual(
            ChordRecognitionCompendium.userFacingCandidateTexts(from: ["EGG", "EG", "E3", "Eb-", "Ebm", "Eb-7"]),
            ["Eb-", "Eb-7"]
        )
    }

    func testParsesMeterWithWhitespace() throws {
        let meter = try MeterParser.parse(" 6/8 ")

        XCTAssertEqual(meter.numerator, 6)
        XCTAssertEqual(meter.denominator, 8)
    }
}
