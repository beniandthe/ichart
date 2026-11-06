#if canImport(UIKit) && canImport(PencilKit)
import XCTest
@testable import iChart

final class EditorToolGuidanceTests: XCTestCase {
    func testWritingGuidanceIdentifiesInputAndRenderingModeAcrossBothLayouts() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for manual in [false, true] {
                let guidance = EditorCanvasMode.chordEntry.toolGuidance(
                    layoutStyle: style, manualRenderWithPreview: manual)
                XCTAssertEqual(guidance.title, "Turn handwriting into chart notation")
                XCTAssertEqual(guidance.steps.count, 2)
                XCTAssertTrue(guidance.steps[0].contains("Apple Pencil"))
                XCTAssertTrue(guidance.steps[0].contains("highlighted lane"))
                XCTAssertTrue(guidance.steps[0].contains("leave space"))
                XCTAssertEqual(guidance.context, manual ? "Rendering: Manual" : "Rendering: Automatic")
                if manual {
                    XCTAssertTrue(guidance.steps[1].contains("Check the previews"))
                    XCTAssertTrue(guidance.steps[1].contains("Render Chords"))
                    XCTAssertTrue(guidance.steps[1].contains("Review & Render"))
                } else {
                    XCTAssertTrue(guidance.steps[1].contains("pause to render"))
                    XCTAssertTrue(guidance.steps[1].contains("Follow the review action when offered"))
                    XCTAssertFalse(guidance.steps[1].contains("Render Chords"))
                }
                // Advanced rules should not displace the next action above
                // the canvas, but must remain available from the same tool.
                XCTAssertFalse(guidance.accessibilitySummary.contains("bar-and-dot"))
                XCTAssertTrue(guidance.referenceText.contains("chord-repeat symbols (%)"))
                XCTAssertTrue(guidance.referenceText.contains("Use Tools > Repeats for measure repeats or ranges."))
                XCTAssertTrue(guidance.referenceText.contains("Drawn bar-and-dot repeat signs are not recognized."))
                XCTAssertTrue(guidance.referenceText.contains("Unplaced ink stays on the page."))
            }
        }
    }

    func testBarlineGuideKeepsLayoutSpecificConstraintsAndLegacyScope() {
        for manual in [false, true] {
            let simple = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: .simpleChordSheet, manualRenderWithPreview: manual)
            let rhythm = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: .rhythmSectionSheet, manualRenderWithPreview: manual)
            let legacy = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: .leadSheet, manualRenderWithPreview: manual)
            XCTAssertTrue(simple.referenceText.contains("Draw tall barlines between chords"))
            XCTAssertFalse(simple.referenceText.contains("rhythmic boundary"))
            XCTAssertTrue(rhythm.referenceText.contains("split at a rhythmic boundary"))
            XCTAssertTrue(rhythm.referenceText.contains("If a note crosses the cut, the line stays as ink."))
            XCTAssertTrue(rhythm.referenceText.contains("empty row end"))
            XCTAssertTrue(rhythm.referenceText.contains("Use Measures for other form edits."))
            XCTAssertFalse(legacy.referenceText.contains("split"))
        }
    }

    func testFreeInkStartsWithHandwritingAndKeepsConversionsInItsGuide() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let guidance = EditorCanvasMode.freeHand.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: false,
                hasFreeInkArticulations: true)
            XCTAssertEqual(guidance.title, "Write notes and reminders on the page")
            XCTAssertTrue(guidance.steps[0].contains("Staff notes stay handwritten"))
            XCTAssertTrue(guidance.steps[1].contains("One finger scrolls"))
            XCTAssertFalse(guidance.accessibilitySummary.contains("fermata"))
            XCTAssertTrue(guidance.referenceText.contains("fermata or accent"))
            XCTAssertTrue(guidance.referenceText.contains("Restore Ink"))
            XCTAssertEqual(guidance.referenceText.contains("marcato"), style == .rhythmSectionSheet)
        }
        let legacy = EditorCanvasMode.freeHand.toolGuidance(
            layoutStyle: .leadSheet, manualRenderWithPreview: false,
            hasFreeInkArticulations: true)
        XCTAssertFalse(legacy.referenceText.contains("Restore Ink"))
        XCTAssertFalse(legacy.referenceText.contains("pause to convert"))
    }

    func testSelectionGuideOnlyOffersConvertedMarkActionsWhenPresent() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let empty = EditorCanvasMode.browse.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: false)
            let withMarks = EditorCanvasMode.browse.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: false,
                hasFreeInkArticulations: true)
            XCTAssertTrue(empty.referenceText.contains("eligible divider"))
            XCTAssertFalse(empty.referenceText.contains("Tap a converted mark"))
            XCTAssertTrue(withMarks.referenceText.contains("Tap a converted mark"))
        }
    }

    func testRecoveryOverridesKeepPurposeModeAndDetailedHelp() {
        let original = EditorCanvasMode.chordEntry.toolGuidance(
            layoutStyle: .rhythmSectionSheet, manualRenderWithPreview: false)
        let recovered = original.replacingNextAction("Erase the highlighted barline, then redraw it.")
        XCTAssertEqual(recovered.title, original.title)
        XCTAssertEqual(recovered.context, original.context)
        XCTAssertEqual(recovered.details, original.details)
        XCTAssertEqual(recovered.steps, ["Erase the highlighted barline, then redraw it."])
        XCTAssertEqual(original.steps.count, 2)
        XCTAssertEqual(original.withContext("Measure 8 selected").context, "Measure 8 selected")
    }

    func testReviewGuideNamesOnlyTheActionsAvailableInItsRenderingMode() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let automatic = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: false)
            let automaticReview = try XCTUnwrap(automatic.details.first { $0.title == "Review prompts" })
            XCTAssertTrue(automaticReview.text.contains("Review Chord to check a chord guess"))
            XCTAssertTrue(automaticReview.text.contains("Fix Writing for unclear or unplaced writing"))
            XCTAssertTrue(automaticReview.text.contains("Review Ending to check an ending's label and measures"))
            XCTAssertFalse(automaticReview.text.contains("Review & Render"))

            let manual = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: true)
            let manualReview = try XCTUnwrap(manual.details.first { $0.title == "Review prompts" })
            XCTAssertTrue(manualReview.text.contains("Review & Render"))
            XCTAssertFalse(manualReview.text.contains("Review Chord"))
            XCTAssertFalse(manualReview.text.contains("Fix Writing"))
            XCTAssertFalse(manualReview.text.contains("Review Ending"))
        }
    }
}
#endif
