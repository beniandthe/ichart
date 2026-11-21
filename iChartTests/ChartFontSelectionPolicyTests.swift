import XCTest
@testable import iChart

final class ChartFontSelectionPolicyTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let premiumFamilies: [ChartFontFamilyPreset] = [.petaluma, .museJazz, .finaleJazz, .finaleAsh]

    func testOnlyNamedFontFamiliesRequireProIncludingFinaleAshAlias() {
        XCTAssertEqual(Set(NotationFontPreset.allCases.filter(\.requiresPremiumFonts)),
            Set([.petaluma, .museJazz, .finaleJazz, .finaleAsh]))
        XCTAssertEqual(Set(ChartFontFamilyPreset.allCases.filter(\.requiresPremiumFonts)),
            Set(premiumFamilies))
        XCTAssertFalse(NotationFontPreset.finaleBroadway.requiresPremiumFonts)
        XCTAssertFalse(ChartFontFamilyPreset.finaleBroadway.requiresPremiumFonts)
    }

    func testFreeCannotApplyPremiumFontToAnyRoleAndKeepsExactChart() {
        for style in styles {
            for family in premiumFamilies {
                let original = Chart.blank(title: "Saved font choices", layoutStyle: style)
                let choices: [ChartFontSelection] = [.matchedSet(family), .chordOverride(family),
                    .headerOverride(family), .textOverride(family), .notation(family == .finaleAsh ? .finaleAsh : family.notationFont)]
                for choice in choices {
                    var chart = original
                    XCTAssertFalse(ChartFontSelectionPolicy.apply(choice, to: &chart, canUsePremiumFonts: false),
                        "\(style) \(choice)")
                    XCTAssertEqual(chart, original, "Denied selection must preserve timestamps, ink, content, and fonts")
                }
            }
        }
    }

    func testProCanApplyNamedFamiliesToEachRoleWithAliasNormalization() {
        for style in styles {
            for family in premiumFamilies {
                let expected = family.releaseSafeTextFamily
                var chart = Chart.blank(title: "Pro fonts", layoutStyle: style)
                XCTAssertTrue(ChartFontSelectionPolicy.apply(.matchedSet(family), to: &chart, canUsePremiumFonts: true))
                XCTAssertEqual(chart.typography.matchedSet, expected)
                XCTAssertEqual(chart.notationFont, expected.notationFont)
                for choice in [ChartFontSelection.chordOverride(family), .headerOverride(family), .textOverride(family)] {
                    XCTAssertTrue(ChartFontSelectionPolicy.apply(choice, to: &chart, canUsePremiumFonts: true))
                }
                XCTAssertEqual(chart.typography.chordOverride, expected)
                XCTAssertEqual(chart.typography.headerOverride, expected)
                XCTAssertEqual(chart.typography.textOverride, expected)
                XCTAssertTrue(ChartFontSelectionPolicy.apply(.notation(family == .finaleAsh ? .finaleAsh : family.notationFont),
                    to: &chart, canUsePremiumFonts: true))
                XCTAssertEqual(chart.notationFont, expected.notationFont)
            }
        }
    }

    func testEveryOtherSelectableFontAndResetToFreeMatchedSetWorksWithoutPro() {
        for style in styles {
            for family in ChartFontFamilyPreset.selectableCases where !family.requiresPremiumFonts {
                var chart = Chart.blank(title: "Basic fonts", layoutStyle: style)
                chart.typography = ChartTypographySettings(matchedSet: .finaleJazz,
                    chordOverride: .petaluma, headerOverride: .museJazz, textOverride: .finaleJazz)
                for choice in [ChartFontSelection.matchedSet(family), .chordOverride(family),
                    .headerOverride(family), .textOverride(family), .chordOverride(nil), .headerOverride(nil), .textOverride(nil)] {
                    XCTAssertTrue(ChartFontSelectionPolicy.apply(choice, to: &chart, canUsePremiumFonts: false))
                }
                XCTAssertEqual(chart.typography.matchedSet, family)
                XCTAssertEqual(chart.typography.resolvedChordFont, family)
                XCTAssertEqual(chart.typography.resolvedHeaderFont, family)
                XCTAssertEqual(chart.typography.resolvedTextFont, family)
            }
            for font in NotationFontPreset.selectableCases where !font.requiresPremiumFonts {
                var chart = Chart.blank(title: "Basic notation", layoutStyle: style)
                let typography = chart.typography
                XCTAssertTrue(ChartFontSelectionPolicy.apply(.notation(font), to: &chart, canUsePremiumFonts: false))
                XCTAssertEqual(chart.notationFont, font)
                XCTAssertEqual(chart.typography, typography, "Notation selection must keep all text roles")
            }
        }
    }

    func testUseMatchedSetCannotBypassPaidFontGate() {
        for style in styles {
            var chart = Chart.blank(title: "Inherited paid font", layoutStyle: style)
            chart.typography = ChartTypographySettings(matchedSet: .finaleJazz,
                chordOverride: .leland, headerOverride: .finaleMaestro, textOverride: .finaleBroadway)
            let original = chart
            for choice in [ChartFontSelection.chordOverride(nil), .headerOverride(nil), .textOverride(nil)] {
                XCTAssertFalse(ChartFontSelectionPolicy.apply(choice, to: &chart, canUsePremiumFonts: false))
                XCTAssertEqual(chart, original)
                var proChart = original
                XCTAssertTrue(ChartFontSelectionPolicy.apply(choice, to: &proChart, canUsePremiumFonts: true))
            }
        }
    }

    func testSavedPremiumAppearanceSurvivesReopenAndFreeEditsWithoutFontSubstitution() throws {
        for style in styles {
            var saved = Chart.blank(title: "Retained paid appearance", layoutStyle: style)
            saved.setNotationFont(.petaluma)
            saved.typography = ChartTypographySettings(matchedSet: .finaleJazz,
                chordOverride: .museJazz, headerOverride: .petaluma, textOverride: .finaleJazz)
            saved.pageHandwrittenNotationData = Data([1, 2, 3, 4])
            saved.pageHandwrittenChordData = Data([5, 6, 7, 8])
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(saved))
            XCTAssertEqual(reopened, saved)
            XCTAssertEqual(ChartTypographyResolver(chart: reopened), ChartTypographyResolver(chart: saved))
            var edited = reopened
            XCTAssertFalse(ChartFontSelectionPolicy.apply(.matchedSet(.finaleJazz), to: &edited, canUsePremiumFonts: false))
            XCTAssertEqual(edited, saved, "Tapping an already saved paid choice must not alter the chart")
            XCTAssertTrue(ChartFontSelectionPolicy.apply(.headerOverride(.leland), to: &edited, canUsePremiumFonts: false))
            XCTAssertEqual(edited.notationFont, saved.notationFont)
            XCTAssertEqual(edited.typography.matchedSet, saved.typography.matchedSet)
            XCTAssertEqual(edited.typography.resolvedChordFont, .museJazz)
            XCTAssertEqual(edited.typography.resolvedTextFont, .finaleJazz)
            XCTAssertEqual(edited.pageHandwrittenNotationData, saved.pageHandwrittenNotationData)
            XCTAssertEqual(edited.pageHandwrittenChordData, saved.pageHandwrittenChordData)
        }
    }
}
