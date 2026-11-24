import XCTest

/// Uses normal tool menus and real canvas taps in a separate process. These
/// fixtures contain no user charts; no private canvas action is invoked.
final class ToolMeasureSelectionUITests: XCTestCase {
    private let fixtureTitles = ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testToolsRowsOpenEveryDestinationFromTheirTrailingBlankAreaInBothStyles() throws {
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        let destinations = [
            (title: "Repeats", purpose: "Repeat measures or add an ending"),
            (title: "Time Signature", purpose: "Change the meter from a measure"),
            (title: "Text", purpose: "Place or edit a text cue"),
            (title: "Form Markers", purpose: "")
        ]
        for title in fixtureTitles {
            openFixture(title, in: app)
            for (index, destination) in destinations.enumerated() {
                tapControlEdge(app.buttons["Tools"], at: 0.94)
                let popover = app.descendants(matching: .any).matching(identifier: "editor-tools-popover").firstMatch
                XCTAssertTrue(popover.waitForExistence(timeout: 5))
                let rows = toolsRows(in: app)
                for row in rows {
                    XCTAssertTrue(row.waitForExistence(timeout: 5))
                    XCTAssertTrue(row.isHittable)
                    XCTAssertTrue(row.isEnabled)
                    XCTAssertGreaterThanOrEqual(row.frame.height, 44)
                    XCTAssertGreaterThanOrEqual(row.frame.width, 220,
                        "Tools must expose the full row, including blank space after short titles")
                    XCTAssertEqual(row.frame.width, rows[0].frame.width, accuracy: 1)
                    XCTAssertTrue(popover.frame.insetBy(dx: -1, dy: -1).contains(row.frame),
                        "Each full-width row must fit inside the Tools accessibility group")
                    XCTAssertTrue(app.windows.firstMatch.frame.contains(row.frame))
                }
                let row = toolsRow(destination.title, in: app)
                if index.isMultiple(of: 2) {
                    // Absolute screen coordinates deliberately land beyond the
                    // icon and title rather than activating the text's center.
                    let point = CGPoint(x: row.frame.maxX - 24, y: row.frame.midY)
                    app.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
                } else {
                    row.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
                }
                waitForRemoval(row, message: "Choosing a Tools row dismisses the popover")
                if destination.title == "Form Markers" {
                    let sheet = app.navigationBars["Form Markers"]
                    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
                    XCTAssertTrue(app.staticTexts["form-marker-instruction"].exists)
                    sheet.buttons["Cancel"].tap()
                    waitForRemoval(sheet, message: "Cancel returns to the chart without adding a form marker")
                    XCTAssertFalse(app.staticTexts["Marker"].exists)
                } else {
                    waitForPurpose(destination.purpose, in: app)
                    if destination.title == "Repeats" {
                        XCTAssertTrue(app.buttons["Start Repeat"].waitForExistence(timeout: 5))
                        XCTAssertTrue(app.buttons["Repeat This Measure"].isHittable)
                        XCTAssertTrue(app.buttons["Add Ending"].exists)
                    } else if destination.title == "Text" {
                        tapFirstRow(at: 0.18, in: app)
                        XCTAssertTrue(app.buttons["Above"].waitForExistence(timeout: 5))
                        XCTAssertTrue(app.buttons["Below"].isHittable)
                    }
                }
                XCTAssertFalse(app.textViews["editor-cue-text-entry"].exists,
                    "Entering a tool must not implicitly open its text field")
                XCTAssertFalse(app.keyboards.firstMatch.exists,
                    "Choosing or canceling a Tools row must not start text input")
            }
            attach(app, name: "\(title) Tools trailing-space rows reach every destination")
            exitChart(in: app)
        }
    }

    @MainActor
    func testToolsOutsideDismissalPreservesTheCurrentToolAndAllowsImmediateReopenInBothStyles() throws {
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            let purpose = app.staticTexts["editor-guidance-purpose"]
            XCTAssertTrue(purpose.waitForExistence(timeout: 5))
            let originalPurpose = purpose.label
            let originalPurposeFrame = purpose.frame
            let context = app.staticTexts["editor-guidance-context"]
            let originalContext = context.exists ? context.label : nil
            tapControlEdge(app.buttons["Tools"], at: 0.94)
            let popover = app.descendants(matching: .any).matching(identifier: "editor-tools-popover").firstMatch
            XCTAssertTrue(popover.waitForExistence(timeout: 5))
            let rows = toolsRows(in: app)
            for row in rows { XCTAssertTrue(row.waitForExistence(timeout: 5)) }
            let point = CGPoint(x: originalPurposeFrame.minX + 2, y: originalPurposeFrame.midY)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(point))
            XCTAssertFalse(popover.frame.contains(point), "Dismissal must tap outside the actual popover")
            XCTAssertTrue(rows.allSatisfy { !$0.frame.contains(point) },
                "Dismissal must tap outside every Tools row")
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
            waitForRemoval(popover, message: "A normal outside tap dismisses Tools")
            XCTAssertTrue(rows.allSatisfy { !$0.exists })
            XCTAssertEqual(purpose.label, originalPurpose)
            XCTAssertEqual(context.exists ? context.label : nil, originalContext)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            tapControlEdge(app.buttons["Tools"], at: 0.06)
            for row in toolsRows(in: app) { XCTAssertTrue(row.waitForExistence(timeout: 5)) }
            tapControlEdge(toolsRow("Text", in: app), at: 0.94)
            waitForPurpose("Place or edit a text cue", in: app)
            waitForRemoval(toolsRow("Text", in: app), message: "Reopened Tools dispatches exactly one row and dismisses")
            app.buttons["Select"].tap()
            waitForPurpose(originalPurpose, in: app)
            attach(app, name: "\(title) Tools dismisses outside and immediately reopens")
            exitChart(in: app)
        }
    }

    @MainActor
    func testChartTitleAndSubtoolMenusOpenFromTheirVisibleEdgesInBothStyles() throws {
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            let settings = app.buttons["editor-document-settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(settings.frame.width, app.windows.firstMatch.frame.width * 0.25)
            XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
            let addPage = app.buttons["Add Page"]
            for offset in [0.04, 0.96] {
                tapControlEdge(settings, at: offset)
                XCTAssertTrue(addPage.waitForExistence(timeout: 5))
                dismissOpenMenu(in: app)
                waitForRemoval(addPage, message: "Dismissing document settings leaves its trigger ready")
            }

            tapControlEdge(app.buttons["Measures"], at: 0.95)
            let add = app.buttons["Add"]
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(add.frame.height, 44)
            tapControlEdge(add, at: 0.06)
            let addOne = app.buttons["Add One After"]
            XCTAssertTrue(addOne.waitForExistence(timeout: 5))
            dismissOpenMenu(in: app)
            waitForRemoval(addOne, message: "Dismissing Add returns to the same tool")
            XCTAssertTrue(add.isHittable)
            exitChart(in: app)
        }
    }

    @MainActor
    func testAddMultipleAndFirstEndingRowsHandOffToExistingSheetsInBothStyles() throws {
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            let selectPurpose = app.staticTexts["editor-guidance-purpose"].label
            app.buttons["Measures"].tap()
            tapFirstRow(at: 0.18, in: app)
            let measure = try selectedMeasure(in: app)
            tapControlEdge(app.buttons["Add"], at: 0.94)
            let multiple = app.buttons["Add Multiple After…"]
            XCTAssertTrue(multiple.waitForExistence(timeout: 5))
            XCTAssertTrue(multiple.isHittable)
            XCTAssertGreaterThanOrEqual(multiple.frame.height, 44)
            // This app-owned Button has no long-press action. A brief hold can
            // expose its pressed outline in an already-running Simulator video;
            // release still invokes the same single existing sheet handoff.
            multiple.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
                .press(forDuration: 0.25)
            let stack = app.navigationBars["Measure Stack"]
            XCTAssertTrue(stack.waitForExistence(timeout: 5))
            waitForRemoval(multiple, message: "The Add popover yields to Measure Stack")
            XCTAssertTrue(stack.buttons["Cancel"].isHittable)
            XCTAssertTrue(stack.buttons["Add"].isEnabled)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            stack.buttons["Cancel"].tap()
            waitForRemoval(stack, message: "Cancel closes Measure Stack without inserting measures")
            waitForContext("Measure \(measure) selected", in: app)
            XCTAssertTrue(app.buttons["Add"].isHittable)

            openTool("Repeats", in: app)
            tapFirstRow(at: 0.18, in: app)
            tapControlEdge(app.buttons["Add Ending"], at: 0.94)
            let firstEnding = app.buttons["1st Ending…"]
            XCTAssertTrue(firstEnding.waitForExistence(timeout: 5))
            tapControlEdge(firstEnding, at: 0.94)
            let ending = app.navigationBars["Add Ending"]
            XCTAssertTrue(ending.waitForExistence(timeout: 5))
            waitForRemoval(firstEnding, message: "The ending popover yields to the existing editor")
            let cancel = app.buttons["ending-editor-cancel"]
            let apply = app.buttons["ending-editor-apply"]
            XCTAssertTrue(cancel.isHittable)
            XCTAssertTrue(apply.isEnabled)
            XCTAssertTrue(app.textFields["ending-editor-label"].exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            cancel.tap()
            waitForRemoval(ending, message: "Cancel closes the ending editor without applying its draft")
            // presentNewEndingEditor deliberately enters Select before opening
            // the sheet; cancel returns there, rather than restoring Repeats.
            waitForPurpose(selectPurpose, in: app)
            attach(app, name: "\(title) Add Multiple and 1st Ending preserve existing sheet handoffs")
            exitChart(in: app)
        }
    }

    @MainActor
    func testRepeatStartAndEndRemainSelectableInBothChartStyles() throws {
        try assertDirectRepeatActions(narrow: false)
    }

    @MainActor
    func testDirectRepeatActionsStayReachableInNarrowWindowsInBothChartStyles() throws {
        try assertDirectRepeatActions(narrow: true)
    }

    @MainActor
    private func assertDirectRepeatActions(narrow: Bool) throws {
        let app = try fixtureApplication(narrow: narrow)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            openTool("Repeats", in: app)

            let initial = try selectedMeasure(in: app)
            tapFirstRow(at: 0.47, in: app)
            let end = try waitForDifferentSelectedMeasure(than: initial, in: app)
            tapFirstRow(at: 0.18, in: app)
            let start = try waitForDifferentSelectedMeasure(than: end, in: app)
            XCTAssertLessThan(start, end)

            let startRepeat = app.buttons["Start Repeat"]
            let repeatThisMeasure = app.buttons["Repeat This Measure"]
            let endRepeat = app.buttons["End Repeat"]
            let cancel = app.buttons["Cancel"]
            let removeRepeat = app.buttons["Remove Repeat"]
            let editEnding = app.buttons["Edit Ending…"]
            let removeEnding = app.buttons["Remove Ending"]
            XCTAssertFalse(app.buttons["Repeat Measures"].exists)
            XCTAssertFalse(app.buttons["Manage"].exists)
            let readyFrames = repeatActionFrames(startRepeat, repeatThisMeasure, in: app)
            for action in [removeRepeat, editEnding, removeEnding] {
                XCTAssertTrue(action.exists, "Existing-mark actions are directly available in Repeats")
                XCTAssertFalse(action.isEnabled, "An empty measure has no mark to edit or remove")
            }
            let canvas = try XCTUnwrap(documentViewport(in: app)).frame
            if narrow {
                XCTAssertLessThanOrEqual(canvas.width, 360, "The narrow fixture must constrain the editor")
            } else {
                XCTAssertGreaterThan(canvas.width, 360, "The standard fixture must exercise the wider editor")
            }

            tapControlEdge(repeatThisMeasure, at: 0.94)
            waitForContext("Measure \(start) selected", in: app)
            XCTAssertTrue(startRepeat.isHittable, "A one-measure repeat commits in one tap")
            XCTAssertFalse(endRepeat.exists)
            XCTAssertTrue(removeRepeat.isEnabled, "Repeat This Measure applies to the selected measure")
            XCTAssertFalse(editEnding.isEnabled, "A repeat alone does not enable ending edits")

            tapFirstRow(at: 0.47, in: app)
            waitForContext("Measure \(end) selected", in: app)
            XCTAssertFalse(removeRepeat.isEnabled, "A different measure cannot remove the saved repeat")
            tapFirstRow(at: 0.18, in: app)
            waitForContext("Measure \(start) selected", in: app)
            tapControlEdge(removeRepeat, at: 0.94)
            XCTAssertFalse(removeRepeat.isEnabled, "The direct action clears the selected repeat in one tap")

            tapControlEdge(startRepeat, at: 0.94)
            waitForContext("Start: \(start) · End: \(start)", in: app)
            XCTAssertFalse(startRepeat.exists)
            XCTAssertFalse(repeatThisMeasure.exists)
            let pendingFrames = repeatActionFrames(endRepeat, cancel, in: app)
            for (ready, pending) in zip(readyFrames, pendingFrames) {
                XCTAssertEqual(ready.midX, pending.midX, accuracy: 2)
                XCTAssertEqual(ready.midY, pending.midY, accuracy: 2)
            }
            let pendingCanvas = try XCTUnwrap(documentViewport(in: app)).frame
            XCTAssertEqual(pendingCanvas.minY, canvas.minY, accuracy: 2,
                "Starting a repeat keeps the chart in the same place")

            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: \(start) · End: \(end)", in: app)
            tapControlEdge(cancel, at: 0.94)
            waitForContext("Measure \(end) selected", in: app)
            XCTAssertTrue(startRepeat.isHittable)
            XCTAssertTrue(repeatThisMeasure.isHittable)
            XCTAssertFalse(endRepeat.exists)
            XCTAssertFalse(cancel.exists)
            XCTAssertFalse(removeRepeat.isEnabled, "Cancel leaves the endpoint without a saved repeat")

            tapFirstRow(at: 0.18, in: app)
            waitForContext("Measure \(start) selected", in: app)
            tapControlEdge(startRepeat, at: 0.94)
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: \(start) · End: \(end)", in: app)
            tapFirstRow(at: 0.18, in: app)
            waitForContext("Start: \(start) · End: \(start)", in: app)
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: \(start) · End: \(end)", in: app)
            tapControlEdge(endRepeat, at: 0.06)
            waitForContext("Measure \(end) selected", in: app)
            XCTAssertTrue(startRepeat.isHittable)
            XCTAssertTrue(repeatThisMeasure.isHittable)
            XCTAssertFalse(endRepeat.exists)
            XCTAssertFalse(cancel.exists)
            XCTAssertTrue(removeRepeat.isEnabled, "End Repeat commits the final endpoint")

            if !narrow {
                tapControlEdge(repeatThisMeasure, at: 0.94)
                tapControlEdge(removeRepeat, at: 0.94)
                let singleRepeat = app.buttons["Repeat · Measure \(end)"]
                XCTAssertTrue(singleRepeat.waitForExistence(timeout: 5),
                    "A shared boundary offers the specific repeat ranges")
                XCTAssertTrue(app.buttons["Repeat · Measures \(start)–\(end)"].exists)
                singleRepeat.tap()
                waitForRemoval(singleRepeat, message: "Removing a marked repeat dismisses the chooser")
                XCTAssertTrue(removeRepeat.isEnabled, "The other repeat at the same boundary stays in place")
            }

            tapFirstRow(at: 0.76, in: app)
            let outside = try waitForDifferentSelectedMeasure(than: end, in: app)
            XCTAssertGreaterThan(outside, end)
            XCTAssertFalse(removeRepeat.isEnabled, "A measure outside the range has no repeat boundary")
            tapFirstRow(at: 0.18, in: app)
            waitForContext("Measure \(start) selected", in: app)
            XCTAssertTrue(removeRepeat.isEnabled, "Either boundary can target the range")
            tapControlEdge(removeRepeat, at: 0.94)
            XCTAssertFalse(removeRepeat.isEnabled)
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Measure \(end) selected", in: app)
            XCTAssertFalse(removeRepeat.isEnabled, "Removing the repeat clears both boundaries")
            attach(app, name: "\(title) direct repeat actions at \(narrow ? "narrow" : "standard") width")
            exitChart(in: app)
        }
    }

    @MainActor
    private func repeatActionFrames(_ first: XCUIElement, _ second: XCUIElement, in app: XCUIApplication) -> [CGRect] {
        let frames = [first, second].map { button in
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(button.isEnabled)
            let frame = button.frame
            XCTAssertGreaterThanOrEqual(frame.height + 0.5, 44)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(frame))
            return frame
        }
        XCTAssertLessThanOrEqual(frames[0].maxX, frames[1].minX)
        XCTAssertEqual(frames[0].midY, frames[1].midY, accuracy: 1)
        return frames
    }

    @MainActor
    func testDirectEndingActionsTrackTheSelectedMeasureInBothChartStyles() throws {
        let app = try fixtureApplication(narrow: true)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            openTool("Repeats", in: app)

            tapFirstRow(at: 0.18, in: app)
            let start = try selectedMeasure(in: app)
            let editEnding = app.buttons["Edit Ending…"]
            let removeEnding = app.buttons["Remove Ending"]
            XCTAssertTrue(editEnding.exists)
            XCTAssertTrue(removeEnding.exists)
            XCTAssertFalse(editEnding.isEnabled)
            XCTAssertFalse(removeEnding.isEnabled)

            tapControlEdge(app.buttons["Add Ending"], at: 0.94)
            let startEnding = app.buttons["Start 1st Ending Here"]
            XCTAssertTrue(startEnding.waitForExistence(timeout: 5))
            tapControlEdge(startEnding, at: 0.94)
            tapFirstRow(at: 0.69, in: app)
            let context = app.staticTexts["editor-guidance-context"]
            let endpointChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard context.exists,
                      let end = Int(context.label.split(separator: " ").last ?? "") else { return false }
                return end > start + 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [endpointChanged], timeout: 5), .completed,
                "The ending must cover an interior measure")
            let end = try XCTUnwrap(Int(context.label.split(separator: " ").last ?? ""))
            tapControlEdge(app.buttons["End 1st"], at: 0.94)
            let addEndingSheet = app.navigationBars["Add Ending"]
            XCTAssertTrue(addEndingSheet.waitForExistence(timeout: 5))
            app.buttons["ending-editor-apply"].tap()
            waitForRemoval(addEndingSheet, message: "Applying creates the ending over the selected range")

            openTool("Repeats", in: app)
            tapFirstRow(at: 0.93, in: app)
            let outside = try selectedMeasure(in: app)
            XCTAssertGreaterThan(outside, end)
            XCTAssertFalse(editEnding.isEnabled, "An unrelated measure cannot edit this ending")
            XCTAssertFalse(removeEnding.isEnabled, "An unrelated measure cannot remove this ending")
            tapFirstRow(at: 0.47, in: app)
            let interior = try waitForDifferentSelectedMeasure(than: outside, in: app)
            XCTAssertGreaterThan(interior, start)
            XCTAssertLessThan(interior, end)
            XCTAssertTrue(editEnding.isEnabled, "A measure inside the bracket can edit the ending")
            XCTAssertTrue(removeEnding.isEnabled, "A measure inside the bracket can remove the ending")
            XCTAssertFalse(app.buttons["Remove Repeat"].isEnabled, "An ending alone does not enable repeat removal")

            tapControlEdge(editEnding, at: 0.94)
            let editEndingSheet = app.navigationBars["Edit Ending"]
            XCTAssertTrue(editEndingSheet.waitForExistence(timeout: 5))
            let label = app.textFields["ending-editor-label"]
            XCTAssertEqual(label.value as? String, "1.")
            app.buttons["Use ending label 2."].tap()
            app.buttons["ending-editor-apply"].tap()
            waitForRemoval(editEndingSheet, message: "The direct edit action saves changes to the existing ending")

            XCTAssertTrue(editEnding.isHittable, "Applying an edit keeps the Repeats tool active")
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Measure \(interior) selected", in: app)
            tapControlEdge(editEnding, at: 0.94)
            XCTAssertTrue(editEndingSheet.waitForExistence(timeout: 5))
            XCTAssertEqual(label.value as? String, "2.")
            app.buttons["ending-editor-cancel"].tap()
            waitForRemoval(editEndingSheet, message: "Cancel leaves the saved ending available")

            waitForContext("Measure \(interior) selected", in: app)
            tapControlEdge(removeEnding, at: 0.94)
            let deleteAlert = app.alerts.firstMatch
            XCTAssertTrue(deleteAlert.waitForExistence(timeout: 5))
            deleteAlert.buttons["Delete Ending"].tap()
            waitForRemoval(deleteAlert, message: "Confirming the direct action removes the targeted ending")
            XCTAssertFalse(editEnding.isEnabled)
            XCTAssertFalse(removeEnding.isEnabled)
            attach(app, name: "\(title) direct ending actions follow the selected measure at narrow width")
            exitChart(in: app)
        }
    }

    @MainActor
    func testMeasuresRangeCancelAndTimeSignatureRetargetingInBothChartStyles() throws {
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            app.buttons["Measures"].tap()
            let initial = try selectedMeasure(in: app)
            tapFirstRow(at: 0.47, in: app)
            let later = try waitForDifferentSelectedMeasure(than: initial, in: app)
            tapFirstRow(at: 0.18, in: app)
            let first = try waitForDifferentSelectedMeasure(than: later, in: app)

            tapControlEdge(app.buttons["Delete"], at: 0.92)
            let range = app.buttons["Delete Range…"]
            XCTAssertTrue(range.waitForExistence(timeout: 5))
            range.tap()
            waitForContext("Delete range: measures \(first)–\(first)", in: app)
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Delete range: measures \(min(first, later))–\(max(first, later))", in: app)
            XCTAssertTrue(app.buttons["Delete To"].isHittable)
            app.buttons["Cancel"].tap()
            waitForContext("Measure \(later) selected", in: app)
            XCTAssertFalse(app.buttons["Delete To"].exists)

            openTool("Time Signature", in: app)
            tapFirstRow(at: 0.18, in: app)
            let threeFour = app.buttons["3/4"]
            XCTAssertTrue(threeFour.waitForExistence(timeout: 5), "The first canvas target opens meter choices")
            waitForContext("Measure \(first) selected", in: app)
            cancelMeterChoices(in: app)
            waitForRemoval(threeFour, message: "Cancel closes the first meter request")

            tapFirstRow(at: 0.47, in: app)
            XCTAssertTrue(threeFour.waitForExistence(timeout: 5), "Another measure can open a fresh meter request")
            waitForContext("Measure \(later) selected", in: app)
            threeFour.tap()
            let scope = app.navigationBars["Apply 3/4"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            scope.buttons["Cancel"].tap()
            waitForRemoval(scope, message: "Cancel closes the scope sheet and releases canvas input")

            tapFirstRow(at: 0.18, in: app)
            XCTAssertTrue(threeFour.waitForExistence(timeout: 5), "The canvas is usable after dismissing the scope sheet")
            waitForContext("Measure \(first) selected", in: app)
            cancelMeterChoices(in: app)
            waitForRemoval(threeFour, message: "The final meter request cancels without changing the chart")
            attach(app, name: "\(title) Measures range and meter dialogs cancel without locking selection")
            exitChart(in: app)
        }
    }

    @MainActor
    func testTextRetargetsAfterGuideAndCuePanelDismissalInBothChartStyles() throws {
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            openTool("Text", in: app)
            let guide = app.buttons["editor-tool-guide-button"]
            XCTAssertTrue(guide.waitForExistence(timeout: 5))
            XCTAssertTrue(guide.isHittable)
            guide.tap()
            let done = app.buttons["editor-tool-guide-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
            waitForRemoval(done, message: "Done closes the local tool guide")

            // Text starts without an implicit measure. Choose one on the
            // page before checking that a later tap retargets the tool.
            tapFirstRow(at: 0.18, in: app)
            let initial = try selectedMeasure(in: app)
            tapFirstRow(at: 0.47, in: app)
            let later = try waitForDifferentSelectedMeasure(than: initial, in: app)
            XCTAssertTrue(app.buttons["Above"].isHittable)
            tapControlEdge(app.buttons["Above"], at: 0.07)
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            let entry = app.textViews["editor-cue-text-entry"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            XCTAssertFalse(entry.hasFocus, "Opening Text leaves the cue field idle")
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            let entryFrame = entry.frame
            let scribble = app.buttons["Scribble"]
            XCTAssertTrue(scribble.waitForExistence(timeout: 5))
            XCTAssertTrue(scribble.isHittable)
            scribble.tap()
            XCTAssertFalse(entry.hasFocus, "Preparing for Scribble must leave the field idle")
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            XCTAssertEqual(entry.frame, entryFrame)
            let keyboard = app.buttons["Keyboard"]
            XCTAssertTrue(keyboard.isHittable)
            keyboard.tap()
            entry.typeText("Discard this cue")
            XCTAssertEqual(entry.value as? String, "Discard this cue")
            XCTAssertEqual(entry.frame.minX, entryFrame.minX, accuracy: 1)
            XCTAssertEqual(entry.frame.minY, entryFrame.minY, accuracy: 1)
            cancel.tap()
            waitForRemoval(cancel, message: "Cancel closes the inline cue panel")
            waitForContext("Measure \(later) selected", in: app)

            tapFirstRow(at: 0.18, in: app)
            let first = try waitForDifferentSelectedMeasure(than: later, in: app)
            XCTAssertTrue(app.buttons["Above"].isHittable)
            XCTAssertTrue(app.buttons["Below"].isHittable)
            waitForContext("Measure \(first) selected", in: app)
            tapControlEdge(app.buttons["Below"], at: 0.93)
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            let add = app.buttons["editor-cue-text-commit"]
            XCTAssertTrue(add.exists)
            let emptyDraft = entry.value as? String ?? ""
            XCTAssertTrue(emptyDraft.isEmpty || emptyDraft == "Cue", "A canceled cue leaves the next draft empty")
            entry.tap()
            entry.typeText("Intro")
            XCTAssertTrue(add.isEnabled)
            add.tap()
            waitForRemoval(entry, message: "Add closes the cue panel")

            app.buttons["Edit"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            XCTAssertEqual(entry.value as? String, "Intro", "Edit reopens the cue saved through Add")
            cancel.tap()
            waitForRemoval(entry, message: "Cancel closes the saved cue editor")
            attach(app, name: "\(title) Text accepts first input and retargets after cancel")
            exitChart(in: app)
        }
    }

    @MainActor
    func testRowMovesFitBothChartStyles() throws {
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            app.buttons["Measures"].tap()
            // The two layouts use different first-row widths and leading
            // signatures. Confirm the selection via the displayed context.
            for x: CGFloat in [0.30, 0.38, 0.21] {
                tapFirstRow(at: x, in: app)
                if try selectedMeasure(in: app) == 2 { break }
            }
            XCTAssertEqual(try selectedMeasure(in: app), 2, title)
            chooseLayoutAction("startNewRow", in: app)
            waitForContext("Measure 2 selected", in: app)

            // Move measure 2 into the singleton row above, then select it
            // from its new location and move it back using the other action.
            chooseLayoutAction("joinRowAbove", in: app)
            tapFirstRow(at: 0.76, in: app)
            waitForContext("Measure 2 selected", in: app)
            chooseLayoutAction("moveToRowBelow", in: app)
            tapFirstRow(at: 0.76, in: app)
            waitForContext("Measure 1 selected", in: app)
            attach(app, name: "\(title) row fits after moving measures in both directions")
            exitChart(in: app)
        }
    }

    @MainActor
    func testAddingToFullRhythmRowKeepsNinthMeasureOnFirstRow() throws {
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        openFixture(fixtureTitles[1], in: app)
        app.buttons["Measures"].tap()
        tapFirstRow(at: 0.18, in: app)
        waitForContext("Measure 1 selected", in: app)

        // Grow the first row through the same Add menu used in a real chart.
        // The final canvas tap checks placement instead of relying on automatic
        // selection of the inserted measure.
        for measure in 2...9 {
            app.buttons["Add"].tap()
            let insert = app.buttons["Add One After"]
            XCTAssertTrue(insert.waitForExistence(timeout: 5))
            tapControlEdge(insert, at: 0.94)
            waitForContext("Measure \(measure) selected", in: app)
        }
        tapFirstRow(at: 0.18, in: app)
        waitForContext("Measure 1 selected", in: app)
        tapFirstRow(at: 0.93, in: app)
        XCTAssertGreaterThanOrEqual(try waitForDifferentSelectedMeasure(than: 1, in: app), 9)
        attach(app, name: "Rhythm Section Sheet keeps at least nine measures in the first row")
    }

    @MainActor
    private func chooseLayoutAction(_ id: String, in app: XCUIApplication) {
        app.buttons["measure-layout-open"].tap()
        let sheet = app.navigationBars["Measure Layout"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let action = app.buttons["measure-layout-action-\(id)"]
        XCTAssertTrue(action.exists)
        XCTAssertTrue(action.isEnabled, "Layout must accept \(id) for this selection")
        action.tap()
        waitForRemoval(sheet, message: "The selected layout action closes the sheet")
    }

    @MainActor
    private func fixtureApplication(narrow: Bool = false) throws -> XCUIApplication {
        #if targetEnvironment(simulator)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-iChartEditorUIPreview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-iChartChartPreviewMode", "collapsed", "-iChartChartsWorkspaceMode", "charts",
            "-iChartHasSeenAccountLanding", "NO", "-iChartHasSeenGuidedTourOffer", "YES"
        ]
        if narrow { app.launchArguments.append("-iChartEditorUINarrow") }
        return app
        #else
        throw XCTSkip("Tool selection regression uses disposable Simulator fixtures only.")
        #endif
    }

    @MainActor
    private func openFixture(_ title: String, in app: XCUIApplication) {
        let chart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 20))
        chart.tap()
        XCTAssertTrue(app.buttons["Tools"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func exitChart(in app: XCUIApplication) {
        app.buttons["Exit Chart"].tap()
        XCTAssertTrue(app.buttons["Select charts"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openTool(_ title: String, in app: XCUIApplication) {
        tapControlEdge(app.buttons["Tools"], at: 0.94)
        let entry = toolsRow(title, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        tapControlEdge(entry, at: 0.94)
        waitForRemoval(entry, message: "The chosen Tools row must release the chart for its next action")
    }

    @MainActor
    private func toolsRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let ids = ["Repeats": "repeats", "Time Signature": "timeSignature",
            "Text": "text", "Form Markers": "formMarkers"]
        guard let id = ids[title] else {
            XCTFail("Unrecognized Tools test destination: \(title)")
            return app.buttons[title]
        }
        return app.buttons["editor-tools-item-\(id)"]
    }

    @MainActor
    private func toolsRows(in app: XCUIApplication) -> [XCUIElement] {
        ["Repeats", "Time Signature", "Text", "Form Markers"].map { toolsRow($0, in: app) }
    }

    @MainActor
    private func waitForPurpose(_ expected: String, in app: XCUIApplication) {
        let purpose = app.staticTexts["editor-guidance-purpose"]
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            purpose.exists && purpose.label == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed,
            "The actual tool destination must be active: \(expected)")
    }

    @MainActor
    private func tapControlEdge(_ button: XCUIElement, at horizontalFraction: CGFloat) {
        XCTAssertTrue(button.isHittable)
        button.coordinate(withNormalizedOffset: CGVector(dx: horizontalFraction, dy: 0.5)).tap()
    }

    @MainActor
    private func dismissOpenMenu(in app: XCUIApplication) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.86)).tap()
    }

    @MainActor
    private func cancelMeterChoices(in app: XCUIApplication) {
        let cancel = app.buttons["Cancel"]
        if cancel.exists && cancel.isHittable {
            cancel.tap()
            return
        }

        // On a regular-width iPad, confirmationDialog is a popover and the
        // system omits the Cancel-role row. A real tap on the noninteractive
        // tool-purpose label outside the popover performs its normal dismissal.
        let purpose = app.staticTexts["editor-guidance-purpose"]
        XCTAssertTrue(purpose.exists)
        let point = CGPoint(x: purpose.frame.midX, y: purpose.frame.midY)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(point))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    @MainActor
    private func tapFirstRow(at horizontalFraction: CGFloat, in app: XCUIApplication) {
        // The blank, single-page fixtures use a 932 × 1200 logical document.
        // At fit width, the scroll view centers the document vertically when
        // it is shorter than the viewport. Measure body y=250 is inside the
        // first system in both styles. The visible selection checks the tap.
        guard let viewport = documentViewport(in: app) else {
            XCTFail("The visible document viewport must be available for a normal canvas tap")
            return
        }
        let frame = viewport.frame
        let fitScale = frame.width / 932
        let verticalInset = max(0, (frame.height - 1_200 * fitScale) / 2)
        let point = CGPoint(x: frame.minX + frame.width * horizontalFraction,
            y: frame.minY + verticalInset + 250 * fitScale)
        XCTAssertTrue(frame.contains(point), "The first-row target is visible inside the canvas")
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        XCTAssertTrue(windowFrame.contains(point))
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - windowFrame.minX, dy: point.y - windowFrame.minY)).tap()
    }

    @MainActor
    private func documentViewport(in app: XCUIApplication) -> XCUIElement? {
        app.scrollViews.allElementsBoundByIndex.filter {
            $0.isHittable && $0.frame.height > 200
        }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    @MainActor
    private func selectedMeasure(in app: XCUIApplication) throws -> Int {
        let context = app.staticTexts["editor-guidance-context"]
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        return try measureNumber(in: context.label)
    }

    @MainActor
    private func waitForDifferentSelectedMeasure(than previous: Int, in app: XCUIApplication) throws -> Int {
        let context = app.staticTexts["editor-guidance-context"]
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            context.exists && context.label != "Measure \(previous) selected"
                && context.label.hasPrefix("Measure ") && context.label.hasSuffix(" selected")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
            "A normal canvas tap must choose another measure while keeping the active tool")
        let selected = try measureNumber(in: context.label)
        XCTAssertNotEqual(selected, previous)
        return selected
    }

    private func measureNumber(in label: String) throws -> Int {
        let parts = label.split(separator: " ")
        guard parts.count == 3, parts[0] == "Measure", parts[2] == "selected",
              let number = Int(parts[1]) else {
            throw NSError(domain: "ToolMeasureSelectionUITests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected a visible selected-measure context, got: \(label)"])
        }
        return number
    }

    @MainActor
    private func waitForContext(_ expected: String, in app: XCUIApplication) {
        let context = app.staticTexts["editor-guidance-context"]
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            context.exists && context.label == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed,
            "The active tool must report its actual selected target: \(expected)")
    }

    @MainActor
    private func waitForRemoval(_ element: XCUIElement, message: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !element.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, message)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
