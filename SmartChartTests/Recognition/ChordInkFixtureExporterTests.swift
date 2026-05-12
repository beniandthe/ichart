import XCTest
@testable import SmartChart

final class ChordInkFixtureExporterTests: XCTestCase {
    func testExportsStableFixtureJsonForAcceptedChordInk() throws {
        let strokes = [
            InkStroke(points: [
                InkPoint(x: 40, y: 12, timeOffset: 0.0),
                InkPoint(x: 20, y: 20, timeOffset: 0.1),
                InkPoint(x: 14, y: 42, timeOffset: 0.2),
                InkPoint(x: 36, y: 56, timeOffset: 0.3)
            ]),
            InkStroke(points: [
                InkPoint(x: 52, y: 14, timeOffset: 0.4),
                InkPoint(x: 52, y: 54, timeOffset: 0.5)
            ])
        ]

        let json = try ChordInkFixtureExporter.fixtureJSONString(
            expectedDisplayText: "Bb",
            strokes: strokes
        )
        let decoded = try JSONDecoder().decode(InkFixtureDocument.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.name, "BFlat")
        XCTAssertEqual(decoded.expectedDisplayText, "Bb")
        XCTAssertEqual(decoded.expectedClusterCount, 2)
        XCTAssertEqual(decoded.expectedTopGlyphs, ["B", "b"])
        XCTAssertEqual(decoded.strokes, strokes)
        XCTAssertTrue(json.contains(#""expectedDisplayText" : "Bb""#))
    }

    func testFixtureExportCanonicalizesAcceptedChordAliases() throws {
        let document = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Cm",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(document.expectedDisplayText, "C-")
        XCTAssertEqual(document.expectedTopGlyphs, ["C", "m"])
        XCTAssertEqual(document.name, "Cm")
    }

    func testFixtureExportCanonicalizesMinorSeventhAliasesToDashMinor() throws {
        let document = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Cm7",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(document.expectedDisplayText, "C-7")
        XCTAssertEqual(document.expectedTopGlyphs, ["C", "m", "7"])
        XCTAssertEqual(document.name, "Cm7")
    }

    func testFixtureExportCanonicalizesMinorNinthEleventhAndThirteenthAliasesToDashMinorExtensions() throws {
        let minorNinth = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Cm9",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let minorEleventh = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Cm11",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let dashMinorThirteenth = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "C-13",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let flatMinorThirteenth = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Bbm13",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(minorNinth.expectedDisplayText, "C-9")
        XCTAssertEqual(minorNinth.expectedTopGlyphs, ["C", "m", "9"])
        XCTAssertEqual(minorNinth.name, "Cm9")
        XCTAssertEqual(minorEleventh.expectedDisplayText, "C-11")
        XCTAssertEqual(minorEleventh.expectedTopGlyphs, ["C", "m", "1", "1"])
        XCTAssertEqual(minorEleventh.name, "Cm11")
        XCTAssertEqual(dashMinorThirteenth.expectedDisplayText, "C-13")
        XCTAssertEqual(dashMinorThirteenth.expectedTopGlyphs, ["C", "-", "1", "3"])
        XCTAssertEqual(dashMinorThirteenth.name, "CMinor13")
        XCTAssertEqual(flatMinorThirteenth.expectedDisplayText, "Bb-13")
        XCTAssertEqual(flatMinorThirteenth.expectedTopGlyphs, ["B", "b", "m", "1", "3"])
        XCTAssertEqual(flatMinorThirteenth.name, "BFlatm13")
    }

    func testFixtureExportPreservesWrittenMinorAliasAfterFlatAccidental() throws {
        let document = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Bbm7",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(document.expectedDisplayText, "Bb-7")
        XCTAssertEqual(document.expectedTopGlyphs, ["B", "b", "m", "7"])
        XCTAssertEqual(document.name, "BFlatm7")
    }

    func testFixtureExportPreservesWrittenMinorAliasAfterSharpAccidental() throws {
        let document = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "F#m7",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(document.expectedDisplayText, "F#-7")
        XCTAssertEqual(document.expectedTopGlyphs, ["F", "#", "m", "7"])
        XCTAssertEqual(document.name, "FSharpm7")
    }

    func testFixtureExportKeepsDashMinorGlyphsWhenDashMinorIsWritten() throws {
        let document = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "C-7",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(document.expectedDisplayText, "C-7")
        XCTAssertEqual(document.expectedTopGlyphs, ["C", "-", "7"])
        XCTAssertEqual(document.name, "CMinor7")
    }

    func testFixtureExportSupportsSixthGlyphs() throws {
        let document = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Bb6",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(document.expectedDisplayText, "Bb6")
        XCTAssertEqual(document.expectedTopGlyphs, ["B", "b", "6"])
        XCTAssertEqual(document.name, "BFlat6")
    }

    func testFixtureExportSupportsAugmentedGlyphs() throws {
        let document = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "F#+",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let aliasDocument = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Caug",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(document.expectedDisplayText, "F#+")
        XCTAssertEqual(document.expectedTopGlyphs, ["F", "#", "+"])
        XCTAssertEqual(document.name, "FSharpAugmented")
        XCTAssertEqual(aliasDocument.expectedDisplayText, "C+")
        XCTAssertEqual(aliasDocument.expectedTopGlyphs, ["C", "+"])
        XCTAssertEqual(aliasDocument.name, "Caug")
    }

    func testFixtureExportCanonicalizesAlterationsToParenthesizedDisplayText() throws {
        let document = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Db7(b9)",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let legacyDocument = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Db7b9",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let parenthesizedSharpNineDocument = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Db7(#9)",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let legacySharpNineDocument = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Db7#9",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let flatFiveDocument = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Db7(b5)",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let legacyFlatFiveDocument = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Db7b5",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let sharpFiveDocument = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Db7(#5)",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(document.expectedDisplayText, "Db7(b9)")
        XCTAssertEqual(document.expectedTopGlyphs, ["D", "b", "7", "b", "9"])
        XCTAssertEqual(document.name, "DFlat7Flat9")
        XCTAssertEqual(legacyDocument.expectedDisplayText, "Db7(b9)")
        XCTAssertEqual(legacyDocument.expectedTopGlyphs, ["D", "b", "7", "b", "9"])
        XCTAssertEqual(legacyDocument.name, "DFlat7Flat9")
        XCTAssertEqual(parenthesizedSharpNineDocument.expectedDisplayText, "Db7(#9)")
        XCTAssertEqual(parenthesizedSharpNineDocument.expectedTopGlyphs, ["D", "b", "7", "#", "9"])
        XCTAssertEqual(parenthesizedSharpNineDocument.name, "DFlat7Sharp9")
        XCTAssertEqual(legacySharpNineDocument.expectedDisplayText, "Db7(#9)")
        XCTAssertEqual(legacySharpNineDocument.expectedTopGlyphs, ["D", "b", "7", "#", "9"])
        XCTAssertEqual(legacySharpNineDocument.name, "DFlat7Sharp9")
        XCTAssertEqual(flatFiveDocument.expectedDisplayText, "Db7(b5)")
        XCTAssertEqual(flatFiveDocument.expectedTopGlyphs, ["D", "b", "7", "b", "5"])
        XCTAssertEqual(flatFiveDocument.name, "DFlat7Flat5")
        XCTAssertEqual(legacyFlatFiveDocument.expectedDisplayText, "Db7(b5)")
        XCTAssertEqual(legacyFlatFiveDocument.expectedTopGlyphs, ["D", "b", "7", "b", "5"])
        XCTAssertEqual(legacyFlatFiveDocument.name, "DFlat7Flat5")
        XCTAssertEqual(sharpFiveDocument.expectedDisplayText, "Db7(#5)")
        XCTAssertEqual(sharpFiveDocument.expectedTopGlyphs, ["D", "b", "7", "#", "5"])
        XCTAssertEqual(sharpFiveDocument.name, "DFlat7Sharp5")
    }

    func testFixtureExportCanonicalizesDiminishedAliasesToSymbolGlyphs() throws {
        let diminished = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Cdim",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let diminishedSeventh = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Cdim7",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(diminished.expectedDisplayText, "C°")
        XCTAssertEqual(diminished.expectedTopGlyphs, ["C", "°"])
        XCTAssertEqual(diminished.name, "Cdim")
        XCTAssertEqual(diminishedSeventh.expectedDisplayText, "C°7")
        XCTAssertEqual(diminishedSeventh.expectedTopGlyphs, ["C", "°", "7"])
        XCTAssertEqual(diminishedSeventh.name, "Cdim7")
    }

    func testFixtureExportCanonicalizesHalfDiminishedAliases() throws {
        let halfDiminished = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Cø7",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )
        let writtenMinorSevenFlatFive = try ChordInkFixtureExporter.fixtureDocument(
            expectedDisplayText: "Cm7b5",
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
        )

        XCTAssertEqual(halfDiminished.expectedDisplayText, "Cø7")
        XCTAssertEqual(halfDiminished.expectedTopGlyphs, ["C", "ø", "7"])
        XCTAssertEqual(halfDiminished.name, "CHalfDiminished7")
        XCTAssertEqual(writtenMinorSevenFlatFive.expectedDisplayText, "Cø7")
        XCTAssertEqual(writtenMinorSevenFlatFive.expectedTopGlyphs, ["C", "m", "7", "b", "5"])
        XCTAssertEqual(writtenMinorSevenFlatFive.name, "Cm7Flat5")
    }

    func testFixtureExportNamesUseReadableChordVocabulary() {
        XCTAssertEqual(ChordInkFixtureExporter.fixtureName(for: "F#"), "FSharp")
        XCTAssertEqual(ChordInkFixtureExporter.fixtureName(for: "C△7"), "CMajor7")
        XCTAssertEqual(ChordInkFixtureExporter.fixtureName(for: "C+"), "CAugmented")
        XCTAssertEqual(ChordInkFixtureExporter.fixtureName(for: "C°7"), "CDiminished7")
        XCTAssertEqual(ChordInkFixtureExporter.fixtureName(for: "Cø7"), "CHalfDiminished7")
        XCTAssertEqual(ChordInkFixtureExporter.fixtureName(for: "Db7(b9)"), "DFlat7Flat9")
        XCTAssertEqual(ChordInkFixtureExporter.fixtureName(for: "Db7(#9)"), "DFlat7Sharp9")
        XCTAssertEqual(ChordInkFixtureExporter.fixtureName(for: "G/B"), "GSlashB")
    }

    func testFixtureExportRejectsUnsupportedOrEmptyFixtures() {
        XCTAssertThrowsError(
            try ChordInkFixtureExporter.fixtureDocument(
                expectedDisplayText: "Cmaj7",
                strokes: [InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: nil)])]
            )
        ) { error in
            XCTAssertEqual(error as? ChordInkFixtureExportError, .unsupportedChord("Cmaj7"))
        }

        XCTAssertThrowsError(
            try ChordInkFixtureExporter.fixtureDocument(
                expectedDisplayText: "C",
                strokes: []
            )
        ) { error in
            XCTAssertEqual(error as? ChordInkFixtureExportError, .emptyInk)
        }
    }
}
