import XCTest
@testable import iChart

final class ChordGlyphTemplateLibraryTests: XCTestCase {
    func testInitialTemplatesCoverPlannedChordGlyphVocabulary() {
        let templateTexts = Set(ChordGlyphTemplateLibrary.initialTemplates.map(\.text))

        XCTAssertEqual(
            templateTexts,
            ["A", "B", "C", "D", "E", "F", "G", "#", "b", "+", "△", "°", "ø", "m", "-", "a", "l", "t", "s", "u", "6", "7", "9", "(", ")", "1", "3", "5", "/"]
        )
    }

    func testInitialTemplatesAreDrawableInkSamples() {
        for template in ChordGlyphTemplateLibrary.initialTemplates {
            XCTAssertFalse(template.strokes.isEmpty, template.text)

            for stroke in template.strokes {
                XCTAssertGreaterThanOrEqual(stroke.points.count, 2, template.text)
                XCTAssertFalse(stroke.bounds.width.isNaN, template.text)
                XCTAssertFalse(stroke.bounds.height.isNaN, template.text)
            }
        }
    }
}
