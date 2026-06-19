import XCTest
@testable import iChart

final class ChartTypographyResolverTests: XCTestCase {
    func testLegacyChartWithoutTypographyDefaultsFromNotationFont() throws {
        var chart = Chart.blank(title: "Legacy Fonts")
        chart.notationFont = .finaleJazz
        let encodedData = try JSONEncoder().encode(chart)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        object.removeValue(forKey: "typography")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decodedChart = try JSONDecoder().decode(Chart.self, from: legacyData)

        XCTAssertEqual(decodedChart.notationFont, .finaleJazz)
        XCTAssertEqual(decodedChart.typography.matchedSet, .finaleJazz)
        XCTAssertNil(decodedChart.typography.chordOverride)
        XCTAssertNil(decodedChart.typography.headerOverride)
        XCTAssertNil(decodedChart.typography.textOverride)
    }

    func testMatchedSetUpdatesRoleDefaultsAndNotationRole() {
        var chart = Chart.blank(title: "Matched Set")

        chart.setMatchedFontFamily(.museJazz)

        XCTAssertEqual(chart.typography.matchedSet, .museJazz)
        XCTAssertEqual(chart.notationFont, .museJazz)
        XCTAssertEqual(chart.typography.resolvedChordFont, .museJazz)
        XCTAssertEqual(chart.typography.resolvedHeaderFont, .museJazz)
        XCTAssertEqual(chart.typography.resolvedTextFont, .museJazz)
    }

    func testRoleOverridesAffectOnlyTheirResolvedRole() {
        var chart = Chart.blank(title: "Overrides")
        chart.setMatchedFontFamily(.petaluma)

        chart.setChordFontOverride(.finaleJazz)
        chart.setHeaderFontOverride(.leland)

        XCTAssertEqual(chart.typography.resolvedChordFont, .finaleJazz)
        XCTAssertEqual(chart.typography.resolvedHeaderFont, .leland)
        XCTAssertEqual(chart.typography.resolvedTextFont, .petaluma)

        chart.setChordFontOverride(nil)

        XCTAssertEqual(chart.typography.resolvedChordFont, .petaluma)
        XCTAssertEqual(chart.typography.resolvedHeaderFont, .leland)
        XCTAssertEqual(chart.typography.resolvedTextFont, .petaluma)
    }

    func testFontResolverMapsChordRoleToLowercaseSafeFinaleJazzFace() {
        let settings = ChartTypographySettings(matchedSet: .petaluma, chordOverride: .finaleJazz)
        let resolver = ChartTypographyResolver(settings: settings, notationFont: .petaluma)

        XCTAssertEqual(resolver.chordFamily, .finaleJazz)
        XCTAssertEqual(resolver.chordFamily.chordTextPostScriptName, "FinaleJazzTextLowercase")
    }

    func testSimpleChordTypographyUsesSharedTextSizeContract() {
        XCTAssertEqual(ChartTypographyResolver.simpleChordPrimaryFontSize, 46, accuracy: 0.001)
        XCTAssertEqual(ChartTypographyResolver.simpleChordSuffixScale, 0.54, accuracy: 0.001)
        XCTAssertEqual(ChartTypographyResolver.simpleChordSlashBassScale, 0.56, accuracy: 0.001)
        XCTAssertEqual(
            ChartTypographyResolver.simpleChordSuffixFontSize(),
            24.84,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChartTypographyResolver.simpleChordSlashBassFontSize(),
            25.76,
            accuracy: 0.001
        )
        XCTAssertEqual(ChartTypographyResolver.simpleChordTokenGapWidth, 2, accuracy: 0.001)
    }

    func testStructuredChordTypographyScalesSuffixesBelowRoots() {
        XCTAssertEqual(ChartTypographyResolver.structuredChordPrimaryFontSize, 18, accuracy: 0.001)
        XCTAssertEqual(ChartTypographyResolver.structuredChordSuffixScale, 0.68, accuracy: 0.001)
        XCTAssertEqual(ChartTypographyResolver.structuredChordSlashBassScale, 0.70, accuracy: 0.001)
        XCTAssertEqual(
            ChartTypographyResolver.structuredChordSuffixFontSize(),
            12.24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChartTypographyResolver.structuredChordSlashBassFontSize(),
            12.6,
            accuracy: 0.001
        )
    }

    func testChordSymbolTokenizationKeepsMusicQualitySymbolsSeparate() {
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(for: chord(root: .b, accidental: .flat, quality: "△", extensions: ["7"])),
            [
                ChordTypographyToken(text: "Bb", role: .primaryText),
                ChordTypographyToken(text: "△", role: .musicSymbol),
                ChordTypographyToken(text: "7", role: .suffixText)
            ]
        )
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(for: chord(root: .c, quality: "°", extensions: ["7"])),
            [
                ChordTypographyToken(text: "C", role: .primaryText),
                ChordTypographyToken(text: "°", role: .musicSymbol),
                ChordTypographyToken(text: "7", role: .suffixText)
            ]
        )
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(for: chord(root: .f, quality: "ø", extensions: ["7"])),
            [
                ChordTypographyToken(text: "F", role: .primaryText),
                ChordTypographyToken(text: "ø", role: .musicSymbol),
                ChordTypographyToken(text: "7", role: .suffixText)
            ]
        )
    }

    func testChordSymbolTokenizationPreservesTextAccidentalsAlterationsAndSlashBass() {
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(
                for: chord(
                    root: .e,
                    quality: "",
                    extensions: ["7"],
                    alterations: ["b9"],
                    slashBass: "Bb"
                )
            ),
            [
                ChordTypographyToken(text: "E", role: .primaryText),
                ChordTypographyToken(text: "7(b9)", role: .suffixText),
                ChordTypographyToken(text: "/Bb", role: .slashBassText)
            ]
        )
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(
                for: chord(
                    root: .g,
                    quality: "",
                    extensions: [],
                    slashBass: "B"
                )
            ),
            [
                ChordTypographyToken(text: "G", role: .primaryText),
                ChordTypographyToken(text: "/B", role: .slashBassText)
            ]
        )
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(for: chord(root: .e, accidental: .flat, quality: "maj", extensions: ["7"])),
            [
                ChordTypographyToken(text: "Eb", role: .primaryText),
                ChordTypographyToken(text: "△", role: .musicSymbol),
                ChordTypographyToken(text: "7", role: .suffixText)
            ]
        )
    }

    func testChordSymbolTokenizationMirrorsCanonicalDisplayOrdering() {
        assertTokenTextMatchesDisplayText(
            chord(root: .f, quality: "alt", extensions: ["7"])
        )
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(for: chord(root: .f, quality: "alt", extensions: ["7"])),
            [
                ChordTypographyToken(text: "F", role: .primaryText),
                ChordTypographyToken(text: "7alt", role: .suffixText)
            ]
        )

        assertTokenTextMatchesDisplayText(
            chord(root: .c, quality: "sus", extensions: ["7"], alterations: ["b9"], slashBass: "G")
        )
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(
                for: chord(root: .c, quality: "sus", extensions: ["7"], alterations: ["b9"], slashBass: "G")
            ),
            [
                ChordTypographyToken(text: "C", role: .primaryText),
                ChordTypographyToken(text: "7sus(b9)", role: .suffixText),
                ChordTypographyToken(text: "/G", role: .slashBassText)
            ]
        )

        assertTokenTextMatchesDisplayText(
            chord(root: .a, quality: "-", extensions: ["6"])
        )
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(for: chord(root: .a, quality: "-", extensions: ["6"])),
            [
                ChordTypographyToken(text: "A", role: .primaryText),
                ChordTypographyToken(text: "m6", role: .suffixText)
            ]
        )

        assertTokenTextMatchesDisplayText(
            chord(root: .d, quality: "-△", extensions: ["7"])
        )
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(for: chord(root: .d, quality: "-△", extensions: ["7"])),
            [
                ChordTypographyToken(text: "D", role: .primaryText),
                ChordTypographyToken(text: "-", role: .suffixText),
                ChordTypographyToken(text: "△", role: .musicSymbol),
                ChordTypographyToken(text: "7", role: .suffixText)
            ]
        )
    }

    private func chord(
        root: ChordRoot,
        accidental: Accidental = .natural,
        quality: String,
        extensions: [String],
        alterations: [String] = [],
        slashBass: String? = nil
    ) -> ChordSymbol {
        ChordSymbol(
            root: root,
            accidental: accidental,
            quality: quality,
            extensions: extensions,
            alterations: alterations,
            slashBass: slashBass
        )
    }

    private func assertTokenTextMatchesDisplayText(
        _ symbol: ChordSymbol,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            ChartTypographyResolver.chordTokens(for: symbol).map(\.text).joined(),
            symbol.displayText,
            file: file,
            line: line
        )
    }
}
