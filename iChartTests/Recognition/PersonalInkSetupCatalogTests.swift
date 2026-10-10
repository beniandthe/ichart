import XCTest
@testable import iChart

final class PersonalInkSetupCatalogTests: XCTestCase {
    func testEverySupportedSymbolHasAnExplicitTeachingPrompt() {
        let symbols = PersonalInkSetupCatalog.symbols
        XCTAssertEqual(Set(symbols.map(\.label)), PersonalInkProfile.glyphLabels)
        XCTAssertEqual(symbols.count, PersonalInkProfile.glyphLabels.count)
        XCTAssertEqual(Set(symbols.map(\.id)).count, symbols.count)
        XCTAssertTrue(symbols.allSatisfy { $0.kind == .glyph && !$0.title.isEmpty })
    }

    func testQuickSetupIncludesMajorSymbolAndPreservesExistingWholeChordCards() {
        XCTAssertTrue(PersonalInkSetupCatalog.coreSymbols.contains { $0.label == "△" && $0.kind == .glyph })
        XCTAssertEqual(PersonalInkSetupCatalog.quickSetup.filter { $0.kind == .chord }.map(\.label),
                       ["Bb7", "Cm7", "G/B"])
        XCTAssertEqual(PersonalInkSetupCatalog.suggestedSetup(for: .init()), PersonalInkSetupCatalog.quickSetup)
    }

    func testWholeChordExamplesAndDuplicateRootsDoNotPretendToTeachMissingSymbols() throws {
        var profile = PersonalInkProfile()
        try profile.learn(strokes: ink, label: "A", kind: .glyph, source: .setup)
        try profile.learn(strokes: shiftedInk, label: "A", kind: .glyph, source: .setup)
        try profile.learn(strokes: ink, label: "Ebmaj7", kind: .chord, source: .explicitCorrection)
        let original = profile
        let missing = PersonalInkSetupCatalog.missingSymbols(in: profile)
        XCTAssertEqual(missing.count, PersonalInkProfile.glyphLabels.count - 1)
        XCTAssertFalse(missing.contains { $0.label == "A" })
        XCTAssertTrue(missing.contains { $0.label == "△" })
        XCTAssertTrue(missing.contains { $0.label == "E" })
        XCTAssertEqual(PersonalInkSetupCatalog.suggestedSetup(for: profile), missing)
        XCTAssertEqual(profile, original, "Planning is read-only, regardless of opt-in state")
        XCTAssertFalse(profile.isEnabled)
    }

    func testSavedSymbolLeavesOnlyThatGapAndFrozenPlanDoesNotShift() throws {
        var profile = PersonalInkProfile()
        let plan = PersonalInkSetupCatalog.missingSymbols(in: profile)
        try profile.learn(strokes: ink, label: plan[0].label, kind: .glyph, source: .setup)
        XCTAssertEqual(PersonalInkSetupCatalog.missingSymbols(in: profile), Array(plan.dropFirst()))
        XCTAssertEqual(plan.count, PersonalInkProfile.glyphLabels.count)
        XCTAssertEqual(plan[0].label, "A", "A running setup uses its frozen plan")
        for prompt in plan.dropFirst() {
            try profile.learn(strokes: ink, label: prompt.label, kind: .glyph, source: .setup)
        }
        XCTAssertTrue(PersonalInkSetupCatalog.missingSymbols(in: profile).isEmpty)
        XCTAssertEqual(PersonalInkSetupCatalog.suggestedSetup(for: profile), PersonalInkSetupCatalog.quickSetup)
    }

    private var ink: [InkStroke] {
        [.init(points: [.init(x: 0, y: 20), .init(x: 10, y: 0), .init(x: 20, y: 20)])]
    }
    private var shiftedInk: [InkStroke] {
        [.init(points: [.init(x: 0, y: 20), .init(x: 11, y: 0), .init(x: 20, y: 20)])]
    }
}
