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
                    XCTAssertTrue(guidance.steps[1].contains("between strokes as you move on"))
                    XCTAssertTrue(guidance.steps[1].contains("Pause to finish the last chord"))
                    XCTAssertTrue(guidance.steps[1].contains("Follow review prompts when offered."))
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

    func testAutomaticCadenceGuideKeepsStructuralWaitLocalAndManualInstructionsUnchanged() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let automatic = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: false)
            let cadence = try XCTUnwrap(automatic.details.first { $0.title == "Automatic rendering" })
            XCTAssertTrue(cadence.text.contains("between strokes as you move on with clear gaps"))
            XCTAssertTrue(cadence.text.contains("A brief pause finishes the last chord"))
            XCTAssertTrue(cadence.text.contains("Barlines and ending brackets wait briefly for their own writing"))
            XCTAssertTrue(cadence.text.contains("keep writing elsewhere while ready chords render"))
            XCTAssertTrue(automatic.steps[1].contains("Follow review prompts when offered."),
                "Review is conditional on an offered prompt while ordinary Automatic writing continues")
            XCTAssertFalse(automatic.steps[1].contains("Review & Render"))

            let manual = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: true)
            XCTAssertNil(manual.details.first { $0.title == "Automatic rendering" })
            XCTAssertEqual(manual.steps[1],
                "Check the previews. Tap Render Chords for ready ink, or Review & Render when entries need attention.")
        }
        XCTAssertTrue(ChordInkWorkflowSettings.automaticRenderingDescription.contains("between strokes as you move on"))
        XCTAssertTrue(ChordInkWorkflowSettings.automaticRenderingDescription.contains("pause to finish the last chord"))
        XCTAssertEqual(ChordInkWorkflowSettings.manualRenderingDescription,
            "Show chord previews while you write, then tap Render Chords or Review & Render when you are ready.")
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

    func testFreeInkExplainerNamesTheTwoSharedSymbolsAndKeepsRecoveryInItsGuide() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            // Free Ink conversion does not depend on Write & Render's mode.
            for manual in [false, true] {
                let guidance = EditorCanvasMode.freeHand.toolGuidance(
                    layoutStyle: style, manualRenderWithPreview: manual,
                    hasFreeInkArticulations: true)
                XCTAssertEqual(guidance.title, "Write notes and reminders on the page")
                XCTAssertEqual(guidance.steps.count, 2)
                XCTAssertTrue(guidance.steps[0].contains("Staff notes stay handwritten"))
                XCTAssertTrue(guidance.steps[1].contains("fermata (arch over a dot)"))
                XCTAssertTrue(guidance.steps[1].contains("accent (>)"))
                XCTAssertTrue(guidance.steps[1].contains("Lift the Pencil and pause to render"))
                XCTAssertTrue(guidance.accessibilitySummary.contains("fermata"))
                XCTAssertFalse(guidance.accessibilitySummary.contains("marcato"))
                XCTAssertTrue(guidance.referenceText.contains("One finger scrolls"))
                XCTAssertTrue(guidance.referenceText.contains("Two fingers pan and zoom"))
                XCTAssertTrue(guidance.referenceText.contains("other handwriting stays on the page"))
                XCTAssertTrue(guidance.referenceText.contains("original strokes"))
                XCTAssertTrue(guidance.referenceText.contains("Restore Ink to replace a converted mark"))
                XCTAssertEqual(guidance.referenceText.contains("marcato"), style == .rhythmSectionSheet)
                let withoutMarks = EditorCanvasMode.freeHand.toolGuidance(
                    layoutStyle: style, manualRenderWithPreview: manual)
                XCTAssertFalse(withoutMarks.referenceText.contains("Restore Ink"),
                    "Restoration is offered after the chart contains a converted mark")
            }
        }
        let legacy = EditorCanvasMode.freeHand.toolGuidance(
            layoutStyle: .leadSheet, manualRenderWithPreview: false,
            hasFreeInkArticulations: true)
        XCTAssertFalse(legacy.referenceText.contains("Restore Ink"))
        XCTAssertFalse(legacy.referenceText.contains("pause to convert"))
        XCTAssertFalse(legacy.accessibilitySummary.contains("fermata"))
        XCTAssertFalse(legacy.accessibilitySummary.contains("accent"))
        XCTAssertTrue(legacy.steps[1].contains("One finger scrolls"))
    }

    func testMeasuresGuideExplainsTheLayoutComparisonAndAvailability() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let guidance = EditorCanvasMode.measureEdit.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: false)
            XCTAssertTrue(guidance.referenceText.contains("Open Layout to compare each action"))
            XCTAssertTrue(guidance.referenceText.contains("read why an option is unavailable"))
            XCTAssertTrue(guidance.referenceText.contains("Tap an available action to apply it"))
            let selectGuide = EditorCanvasMode.browse.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: false)
            if style == .rhythmSectionSheet {
                XCTAssertTrue(guidance.accessibilitySummary.contains("right arrow left"))
                XCTAssertTrue(guidance.referenceText.contains("When you release, a lone measure on the next row moves up if its full width fits."))
                XCTAssertTrue(selectGuide.referenceText.contains("Manual row or page breaks and key changes keep their boundaries."))
            } else {
                XCTAssertEqual(guidance.steps, ["Tap a measure, then choose Add, Layout, or Delete."])
                XCTAssertFalse(guidance.referenceText.contains("lone measure on the next row"))
                XCTAssertFalse(selectGuide.referenceText.contains("lone measure on the next row"))
            }
        }
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

    func testSelectionGuideExplainsDirectChordDragAndSeparateControlsInBothStyles() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for manual in [false, true] {
                let guidance = EditorCanvasMode.browse.toolGuidance(
                    layoutStyle: style, manualRenderWithPreview: manual)
                XCTAssertTrue(guidance.steps.joined().contains("Use Apple Pencil to select, move, or delete"))
                XCTAssertTrue(guidance.steps.joined().contains("Scroll with a finger"))
                XCTAssertTrue(guidance.referenceText.contains("Drag a chord with Apple Pencil, then lift to place it"))
                XCTAssertTrue(guidance.referenceText.contains("tap the red X to delete"))
                XCTAssertTrue(guidance.referenceText.contains("drag the width handle to change width"))
                XCTAssertTrue(guidance.referenceText.contains("Double-tap a chord to correct it"))
            }
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
