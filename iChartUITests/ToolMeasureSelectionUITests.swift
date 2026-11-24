import XCTest

/// Uses the editor controls and real canvas taps in a separate process. These
/// fixtures contain no user charts; no private canvas action is invoked.
final class ToolMeasureSelectionUITests: XCTestCase {
    private let fixtureTitles = ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"]
    private let layoutActionIDs = ["startNewRow", "joinRowAbove", "moveToRowBelow", "evenRowWidths", "mergeWithNext"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSidebarRoutesOpenTopActionsInBothChartStyles() throws {
        try assertSidebarRoutes(narrow: false)
    }

    @MainActor
    func testSidebarRoutesOpenTopActionsInNarrowWindowsInBothChartStyles() throws {
        try assertSidebarRoutes(narrow: true)
    }

    @MainActor
    func testQuickActionsHideAndOpenInBothChartStyles() throws {
        try assertQuickActionsVisibility(narrow: false)
    }

    @MainActor
    func testQuickActionsHideAndOpenInNarrowWindowsInBothChartStyles() throws {
        try assertQuickActionsVisibility(narrow: true)
    }

    @MainActor
    private func assertQuickActionsVisibility(narrow: Bool) throws {
        let app = try fixtureApplication(narrow: narrow)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            let quickActionsTitle = app.staticTexts["editor-quick-actions-title"]
            let toggle = app.buttons["editor-quick-actions-toggle"]
            let sidebarRepeat = app.buttons["editor-sidebar-repeat"]
            let layoutAction = app.buttons["measure-layout-action-evenRowWidths"]
            XCTAssertTrue(quickActionsTitle.waitForExistence(timeout: 5))
            XCTAssertEqual(quickActionsTitle.label, "Quick Actions")
            XCTAssertEqual(toggle.label, "Hide")
            XCTAssertEqual(toggle.value as? String, "Open")
            XCTAssertTrue(sidebarRepeat.isHittable)
            XCTAssertTrue(layoutAction.exists)

            let openCanvas = try XCTUnwrap(documentViewport(in: app)).frame
            tapControlEdge(toggle, at: 0.75)
            XCTAssertEqual(toggle.label, "Open")
            XCTAssertEqual(toggle.value as? String, "Hidden")
            XCTAssertFalse(sidebarRepeat.exists)
            XCTAssertFalse(layoutAction.exists)
            let hiddenCanvas = try XCTUnwrap(documentViewport(in: app)).frame
            if narrow {
                XCTAssertEqual(hiddenCanvas.width, openCanvas.width, accuracy: 2)
                XCTAssertLessThan(hiddenCanvas.minY, openCanvas.minY - 16)
                XCTAssertGreaterThan(hiddenCanvas.height, openCanvas.height + 16)
            } else {
                XCTAssertLessThan(hiddenCanvas.minX, openCanvas.minX - 16)
                XCTAssertGreaterThan(hiddenCanvas.width, openCanvas.width + 16)
            }
            attach(app, name: "\(title) with Quick Actions hidden at \(narrow ? "360 points" : "standard width")")

            tapControlEdge(toggle, at: 0.75)
            XCTAssertEqual(toggle.label, "Hide")
            XCTAssertTrue(sidebarRepeat.isHittable)
            XCTAssertTrue(layoutAction.exists)
            let restoredCanvas = try XCTUnwrap(documentViewport(in: app)).frame
            XCTAssertEqual(restoredCanvas.minX, openCanvas.minX, accuracy: 2)
            XCTAssertEqual(restoredCanvas.minY, openCanvas.minY, accuracy: 2)
            XCTAssertEqual(restoredCanvas.width, openCanvas.width, accuracy: 2)

            // Toggling the rail while placing a repeat keeps the in-flight range.
            tapFirstRow(at: 0.47, in: app)
            let end = try selectedMeasure(in: app)
            tapFirstRow(at: 0.18, in: app)
            let start = try waitForDifferentSelectedMeasure(than: end, in: app)
            XCTAssertLessThan(start, end)
            tapControlEdge(sidebarRepeat, at: 0.94)
            waitForContext("Start: \(start) · End: \(start)", in: app)
            let topEnd = topRepeatAction("End Repeat", in: app)
            XCTAssertFalse(topEnd.exists)
            XCTAssertEqual(sidebarRepeat.label, "End Repeat")
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(cancel.isHittable)
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: \(start) · End: \(end)", in: app)

            tapControlEdge(toggle, at: 0.75)
            waitForContext("Start: \(start) · End: \(end)", in: app)
            XCTAssertTrue(topEnd.waitForExistence(timeout: 5), "A hidden rail leaves a way to finish")
            XCTAssertTrue(topEnd.isHittable)
            XCTAssertTrue(cancel.isHittable)
            XCTAssertFalse(sidebarRepeat.exists)

            tapControlEdge(toggle, at: 0.75)
            waitForContext("Start: \(start) · End: \(end)", in: app)
            XCTAssertFalse(topEnd.exists)
            XCTAssertEqual(sidebarRepeat.label, "End Repeat")
            XCTAssertTrue(cancel.isHittable)
            tapControlEdge(sidebarRepeat, at: 0.06)
            waitForContext("Measure \(end) selected", in: app)
            XCTAssertEqual(sidebarRepeat.label, "Start Repeat")
            XCTAssertTrue(app.buttons["Remove Repeat"].isEnabled, "The sidebar commits the retained range")
            exitChart(in: app)
        }
    }

    @MainActor
    private func assertSidebarRoutes(narrow: Bool) throws {
        let app = try fixtureApplication(narrow: narrow)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            XCTAssertFalse(app.buttons["Tools"].exists)
            let canvas = try XCTUnwrap(documentViewport(in: app)).frame
            let sidebarEntries = ["repeat", "text", "form-markers", "time-signature"]
            for id in sidebarEntries {
                let button = app.buttons["editor-sidebar-\(id)"]
                XCTAssertTrue(button.waitForExistence(timeout: 5), id)
                XCTAssertTrue(button.isHittable, id)
                XCTAssertGreaterThanOrEqual(button.frame.height + 0.5, 44, id)
                XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(button.frame), id)
                if narrow {
                    XCTAssertLessThanOrEqual(button.frame.maxY, canvas.minY + 1, id)
                } else {
                    XCTAssertLessThanOrEqual(button.frame.maxX, canvas.minX + 1, id)
                }
            }

            openTool("Repeats", in: app)
            waitForPurpose("Repeat measures or add an ending", in: app)
            XCTAssertTrue(topRepeatAction("Start Repeat", in: app).isHittable)
            XCTAssertTrue(app.buttons["Repeat This Measure"].isHittable)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "editor-tools-popover").firstMatch.exists)

            openTool("Text", in: app)
            waitForPurpose("Place or edit a text cue", in: app)
            tapFirstRow(at: 0.18, in: app)
            XCTAssertTrue(app.buttons["Above"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Below"].isHittable)
            XCTAssertFalse(app.textViews["editor-cue-text-entry"].exists,
                "Opening Add Text leaves input idle while choosing a position")
            XCTAssertFalse(app.keyboards.firstMatch.exists)

            openTool("Form Markers", in: app)
            let segno = app.buttons["form-marker-option-segno"]
            XCTAssertTrue(segno.waitForExistence(timeout: 5))
            XCTAssertTrue(segno.isHittable, "Form Markers offers direct marker buttons")
            XCTAssertFalse(app.navigationBars["Form Markers"].exists)
            try assertPickerRowsCentered("form-marker-option-", in: app)
            attach(app, name: "\(title) centered Form Markers at \(narrow ? "360 points" : "standard width")")
            tapFirstRow(at: 0.47, in: app)
            XCTAssertGreaterThan(try selectedMeasure(in: app), 1, "Form Markers can retarget the chart")

            openTool("Time Signature", in: app)
            waitForPurpose("Change the meter from a measure", in: app)
            let meter = app.buttons["editor-time-signature-3-4"]
            XCTAssertTrue(meter.waitForExistence(timeout: 5))
            XCTAssertTrue(meter.isHittable)
            XCTAssertTrue(app.buttons["editor-time-signature-custom"].isHittable)
            XCTAssertFalse(app.navigationBars["Apply 3/4"].exists,
                "Opening the tool allows target selection before applying a meter")
            try assertPickerRowsCentered("editor-time-signature-", in: app)
            attach(app, name: "\(title) centered Time Signature at \(narrow ? "360 points" : "standard width")")
            exitChart(in: app)
        }
    }

    @MainActor
    private func assertPickerRowsCentered(_ identifierPrefix: String, in app: XCUIApplication) throws {
        let canvas = try XCTUnwrap(documentViewport(in: app)).frame
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
        XCTAssertGreaterThan(choices.count, 1)
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.isHittable)
        let frames = (choices.allElementsBoundByIndex + [done]).map(\.frame).sorted { $0.minY < $1.minY }
        var rows: [CGRect] = []
        for frame in frames {
            XCTAssertLessThanOrEqual(frame.maxY, canvas.minY + 1, "Picker buttons are above the chart")
            if let last = rows.last, frame.minY < last.maxY - 2 {
                rows[rows.count - 1] = last.union(frame)
            } else {
                rows.append(frame)
            }
        }
        for row in rows {
            XCTAssertEqual(row.midX, canvas.midX, accuracy: 4, "Each picker row centers over the chart")
        }
    }

    @MainActor
    func testChartTitleAndMeasuresOpenFromTheirVisibleEdgesInBothStyles() throws {
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
            XCTAssertTrue(app.buttons["measure-layout-action-evenRowWidths"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Add One After"].isHittable)
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
            XCTAssertTrue(stack.buttons["Cancel"].isHittable)
            XCTAssertTrue(stack.buttons["Add"].isEnabled)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            stack.buttons["Cancel"].tap()
            waitForRemoval(stack, message: "Cancel closes Measure Stack without inserting measures")
            waitForContext("Measure \(measure) selected", in: app)
            XCTAssertTrue(multiple.isHittable)

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

            let startRepeat = topRepeatAction("Start Repeat", in: app)
            let sidebarRepeat = app.buttons["editor-sidebar-repeat"]
            let repeatThisMeasure = app.buttons["Repeat This Measure"]
            let endRepeat = topRepeatAction("End Repeat", in: app)
            let cancel = app.buttons["Cancel"]
            let removeRepeat = app.buttons["Remove Repeat"]
            let editEnding = app.buttons["Edit Ending…"]
            let removeEnding = app.buttons["Remove Ending"]
            XCTAssertFalse(app.buttons["Repeat Measures"].exists)
            XCTAssertFalse(app.buttons["Manage"].exists)
            let readyFrames = repeatActionFrames(startRepeat, repeatThisMeasure, in: app)
            XCTAssertEqual(sidebarRepeat.label, "Start Repeat")
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

            // Start in Select using the sidebar, then cancel with the top action.
            app.buttons["Select"].tap()
            waitForPurpose("Edit items on the chart", in: app)
            tapControlEdge(sidebarRepeat, at: 0.94)
            waitForPurpose("Repeat measures or add an ending", in: app)
            waitForContext("Start: \(start) · End: \(start)", in: app)
            XCTAssertEqual(sidebarRepeat.label, "End Repeat")
            XCTAssertFalse(startRepeat.exists)
            XCTAssertFalse(repeatThisMeasure.exists)
            XCTAssertFalse(endRepeat.exists, "Sidebar placement has just one End Repeat action")
            XCTAssertTrue(cancel.isHittable)

            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: \(start) · End: \(end)", in: app)
            tapControlEdge(cancel, at: 0.94)
            waitForContext("Measure \(end) selected", in: app)
            XCTAssertTrue(startRepeat.isHittable)
            XCTAssertTrue(repeatThisMeasure.isHittable)
            XCTAssertFalse(endRepeat.exists)
            XCTAssertFalse(cancel.exists)
            XCTAssertFalse(removeRepeat.isEnabled, "Cancel leaves the endpoint without a saved repeat")
            XCTAssertEqual(sidebarRepeat.label, "Start Repeat")

            tapFirstRow(at: 0.18, in: app)
            waitForContext("Measure \(start) selected", in: app)
            tapControlEdge(startRepeat, at: 0.94)
            let pendingFrames = repeatActionFrames(endRepeat, cancel, in: app)
            for (ready, pending) in zip(readyFrames, pendingFrames) {
                XCTAssertEqual(ready.midX, pending.midX, accuracy: 2)
                XCTAssertEqual(ready.midY, pending.midY, accuracy: 2)
            }
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: \(start) · End: \(end)", in: app)
            tapFirstRow(at: 0.18, in: app)
            waitForContext("Start: \(start) · End: \(start)", in: app)
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: \(start) · End: \(end)", in: app)
            XCTAssertEqual(sidebarRepeat.label, "Start Repeat")
            XCTAssertFalse(sidebarRepeat.isEnabled, "Toolbar placement has no second active repeat control")
            tapControlEdge(endRepeat, at: 0.06)
            waitForContext("Measure \(end) selected", in: app)
            XCTAssertEqual(sidebarRepeat.label, "Start Repeat")
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
    func testRepeatInsertionPlacementInBothChartStyles() throws {
        try assertRepeatInsertionPlacement(narrow: false)
    }

    @MainActor
    func testRepeatInsertionPlacementInNarrowWindowsInBothChartStyles() throws {
        try assertRepeatInsertionPlacement(narrow: true)
    }

    @MainActor
    private func assertRepeatInsertionPlacement(narrow: Bool) throws {
        let app = try fixtureApplication(narrow: narrow)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            openTool("Repeats", in: app)
            tapFirstRow(at: 0.18, in: app)
            waitForContext("Measure 1 selected", in: app)
            tapControlEdge(app.buttons["Repeat This Measure"], at: 0.94)
            let removeRepeat = app.buttons["Remove Repeat"]
            XCTAssertTrue(removeRepeat.isEnabled, "The fixture now has a repeat around measure 1")

            app.buttons["Measures"].tap()
            waitForContext("Measure 1 selected", in: app)
            let addInside = app.buttons["Add Inside Repeat"]
            let addAfter = app.buttons["Add After Repeat"]
            let addMultiple = app.buttons["Add Multiple…"]
            for action in [addInside, addAfter, addMultiple] {
                XCTAssertTrue(action.exists && action.isHittable, "Repeat insertions are direct actions")
                XCTAssertGreaterThanOrEqual(action.frame.height, 44)
                XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(action.frame))
            }
            XCTAssertFalse(app.buttons["Add One After"].exists, "A repeat close gives a placement choice")
            attach(app, name: "\(title) repeat insertion controls at \(narrow ? "narrow" : "standard") width")

            tapControlEdge(addAfter, at: 0.94)
            waitForContext("Measure 2 selected", in: app)
            XCTAssertTrue(app.buttons["Add One After"].exists)
            XCTAssertFalse(addInside.exists, "The new measure is outside the repeat")
            openTool("Repeats", in: app)
            XCTAssertFalse(removeRepeat.isEnabled, "After Repeat leaves the old closing boundary in place")

            // Test the inside action on a second repeat using the current
            // selection. This avoids guessing the first bar's frame after reflow.
            tapControlEdge(app.buttons["Repeat This Measure"], at: 0.94)
            XCTAssertTrue(removeRepeat.isEnabled)
            app.buttons["Measures"].tap()
            XCTAssertTrue(addInside.waitForExistence(timeout: 5))
            tapControlEdge(addInside, at: 0.94)
            waitForContext("Measure 3 selected", in: app)
            XCTAssertTrue(addAfter.isHittable, "The new measure owns the closing repeat after an inside insert")
            openTool("Repeats", in: app)
            XCTAssertTrue(removeRepeat.isEnabled, "Inside Repeat moves the closing repeat to the inserted measure")

            app.buttons["Measures"].tap()
            tapControlEdge(addMultiple, at: 0.94)
            let stack = app.navigationBars["Measure Stack"]
            XCTAssertTrue(stack.waitForExistence(timeout: 5))
            let outside = app.segmentedControls.buttons["After Repeat"]
            let inside = app.segmentedControls.buttons["Inside Repeat"]
            XCTAssertTrue(outside.isSelected, "The stack defaults to adding after the repeat")
            inside.tap()
            XCTAssertTrue(inside.isSelected)
            app.buttons["2"].tap()
            stack.buttons["Add"].tap()
            waitForRemoval(stack, message: "Adding two inside measures dismisses Measure Stack")
            waitForContext("Measure 5 selected", in: app)
            XCTAssertTrue(addAfter.isHittable, "The last added measure owns the repeat's closing barline")
            exitChart(in: app)
        }
    }

    @MainActor
    func testLayoutActionsStayVisibleAcrossToolsInBothChartStyles() throws {
        try assertPersistentLayoutActions(narrow: false)
    }

    @MainActor
    func testLayoutActionsStayVisibleAcrossToolsInNarrowWindowsInBothChartStyles() throws {
        try assertPersistentLayoutActions(narrow: true)
    }

    @MainActor
    private func assertPersistentLayoutActions(narrow: Bool) throws {
        let app = try fixtureApplication(narrow: narrow)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            let startNewRow = app.buttons["measure-layout-action-startNewRow"]
            let joinRowAbove = app.buttons["measure-layout-action-joinRowAbove"]
            let evenMeasures = app.buttons["measure-layout-action-evenRowWidths"]
            XCTAssertTrue(startNewRow.waitForExistence(timeout: 5))
            let selectPurpose = app.staticTexts["editor-guidance-purpose"].label
            let unselectedCanvas = try XCTUnwrap(documentViewport(in: app)).frame
            assertLayoutActionsVisible(narrow: narrow, canvas: unselectedCanvas, in: app)
            assertLayoutActionsDisabled(in: app)

            tapFirstRow(at: 0.47, in: app)
            let target = try selectedMeasure(in: app)
            XCTAssertGreaterThan(target, 1)
            let selectedCanvas = try XCTUnwrap(documentViewport(in: app)).frame
            XCTAssertEqual(selectedCanvas.minX, unselectedCanvas.minX, accuracy: 2)
            XCTAssertEqual(selectedCanvas.width, unselectedCanvas.width, accuracy: 2)
            XCTAssertEqual(evenMeasures.label, "Even System Measures")
            XCTAssertTrue(evenMeasures.isEnabled && evenMeasures.isHittable)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Even Row")).firstMatch.exists)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Join Row Above")).count, 1)
            XCTAssertFalse(joinRowAbove.isEnabled, "There is no destination above the first system")

            chooseLayoutAction("startNewRow", in: app)
            waitForPurpose(selectPurpose, in: app)
            waitForContext("Measure \(target) selected", in: app)
            XCTAssertTrue(joinRowAbove.isEnabled, "The selected measure now starts a system with one above it")
            chooseLayoutAction("joinRowAbove", in: app)
            waitForPurpose(selectPurpose, in: app)
            waitForContext("Measure \(target) selected", in: app)
            XCTAssertFalse(joinRowAbove.isEnabled, "The selected measure is back in the first system")

            openTool("Repeats", in: app)
            waitForPurpose("Repeat measures or add an ending", in: app)
            waitForContext("Measure \(target) selected", in: app)
            assertLayoutActionsVisible(narrow: narrow,
                canvas: try XCTUnwrap(documentViewport(in: app)).frame, in: app)
            assertLayoutActionsDisabled(in: app)

            let inkTools = [
                (button: "Write & Render", purpose: "Turn handwriting into chart notation"),
                (button: "Free Ink", purpose: "Write notes and reminders on the page")
            ]
            for tool in inkTools {
                app.buttons[tool.button].firstMatch.tap()
                waitForPurpose(tool.purpose, in: app)
                let canvas = try XCTUnwrap(documentViewport(in: app)).frame
                assertLayoutActionsVisible(narrow: narrow, canvas: canvas, in: app)
                XCTAssertEqual(canvas.minX, unselectedCanvas.minX, accuracy: 2)
                XCTAssertEqual(canvas.width, unselectedCanvas.width, accuracy: 2)
                assertLayoutActionsDisabled(in: app)
            }

            app.buttons["Measures"].tap()
            waitForPurpose("Change measures and rows", in: app)
            XCTAssertTrue(app.buttons["Add One After"].isHittable)
            tapFirstRow(at: 0.47, in: app)
            XCTAssertTrue(evenMeasures.isEnabled && evenMeasures.isHittable)
            attach(app, name: "\(title) shared Layout actions at \(narrow ? "360 points" : "standard width")")
            exitChart(in: app)
        }
    }

    @MainActor
    func testDirectMeasureActionsRetargetInBothChartStyles() throws {
        try assertDirectMeasureActions(narrow: false)
    }

    @MainActor
    func testDirectMeasureActionsStayReachableInNarrowWindowsInBothChartStyles() throws {
        try assertDirectMeasureActions(narrow: true)
    }

    @MainActor
    private func assertDirectMeasureActions(narrow: Bool) throws {
        let app = try fixtureApplication(narrow: narrow)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            tapFirstRow(at: 0.47, in: app)
            let target = try selectedMeasure(in: app)
            XCTAssertGreaterThan(target, 1, "Use an ordinary measure away from the opening barline")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Measures")).count, 1,
                "The toolbar is the only entry to Measures even after selecting a measure")
            let startNewRow = app.buttons["measure-layout-action-startNewRow"]
            XCTAssertTrue(startNewRow.exists && startNewRow.isEnabled, "Select uses the same Layout controls")
            XCTAssertEqual(app.buttons["measure-layout-action-evenRowWidths"].label, "Even System Measures")
            let selectViewport = try XCTUnwrap(documentViewport(in: app)).frame

            app.buttons["Measures"].tap()
            waitForPurpose("Change measures and rows", in: app)
            waitForContext("Measure \(target) selected", in: app)
            let viewport = try XCTUnwrap(documentViewport(in: app))
            let readyViewport = viewport.frame
            if narrow {
                XCTAssertLessThan(readyViewport.width, 360, "Use the compact tool layout")
                XCTAssertEqual(readyViewport.width, selectViewport.width, accuracy: 2,
                    "The inline actions preserve the available chart width")
            } else {
                XCTAssertGreaterThan(readyViewport.width, 600, "Use the regular tool layout")
            }
            let controls = ["Add One After", "Add Multiple After…", "Add at Beginning", "Add Double Barline",
                            "Delete Measure…", "Delete Range…", "Done"]
            for control in controls {
                let button = app.buttons[control]
                XCTAssertTrue(button.exists && button.isHittable, "\(control) is a direct action")
                XCTAssertGreaterThanOrEqual(button.frame.height, 44, control)
                XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(button.frame), control)
            }
            XCTAssertFalse(app.buttons["Add"].exists)
            XCTAssertFalse(app.buttons["Delete"].exists)
            XCTAssertFalse(app.buttons["measure-layout-open"].exists)
            XCTAssertFalse(app.navigationBars["Measure Layout"].exists)
            assertLayoutActionsVisible(narrow: narrow, canvas: readyViewport, in: app)
            if narrow {
                XCTAssertGreaterThanOrEqual(startNewRow.frame.minY, app.buttons["Add One After"].frame.maxY - 1)
            }
            XCTAssertTrue(startNewRow.isEnabled, "An interior measure can start a row")
            XCTAssertFalse(app.buttons["measure-layout-action-joinRowAbove"].isEnabled,
                "The first row has no destination above it")
            attach(app, name: "\(title) Measures controls at \(narrow ? "360 points" : "standard width")")

            let deleteMeasure = app.buttons["Delete Measure…"]
            let deleteRange = app.buttons["Delete Range…"]
            let deleteMeasureFrame = deleteMeasure.frame
            let deleteRangeFrame = deleteRange.frame
            tapControlEdge(deleteRange, at: 0.94)
            waitForContext("Delete range: measures \(target)–\(target)", in: app)
            let deleteTo = app.buttons["Delete To"]
            let cancelRange = app.buttons["Cancel"]
            XCTAssertFalse(startNewRow.isEnabled, "Row actions wait while a delete range is being selected")
            XCTAssertTrue(deleteTo.isHittable)
            XCTAssertTrue(cancelRange.isHittable)
            XCTAssertEqual(deleteTo.frame.midX, deleteRangeFrame.midX, accuracy: 2)
            XCTAssertEqual(deleteTo.frame.midY, deleteRangeFrame.midY, accuracy: 2)
            XCTAssertEqual(cancelRange.frame.midX, deleteMeasureFrame.midX, accuracy: 2)
            XCTAssertEqual(cancelRange.frame.midY, deleteMeasureFrame.midY, accuracy: 2)
            XCTAssertEqual(viewport.frame.minY, readyViewport.minY, accuracy: 2)
            tapFirstRow(at: 0.18, in: app)
            waitForContext("Delete range: measures 1–\(target)", in: app)
            XCTAssertEqual(deleteTo.frame.midX, deleteRangeFrame.midX, accuracy: 2)
            XCTAssertEqual(cancelRange.frame.midX, deleteMeasureFrame.midX, accuracy: 2)
            XCTAssertEqual(viewport.frame.minY, readyViewport.minY, accuracy: 2)
            cancelRange.tap()
            waitForContext("Measure 1 selected", in: app)
            XCTAssertFalse(deleteTo.exists)
            XCTAssertFalse(startNewRow.isEnabled, "Retargeting to the first measure disables Start New Row")
            XCTAssertEqual(viewport.frame.minX, readyViewport.minX, accuracy: 2)
            XCTAssertEqual(viewport.frame.width, readyViewport.width, accuracy: 2)

            // A repeat on this specific measure proves which measure survives
            // cancellation and which measure is removed on confirmation.
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Measure \(target) selected", in: app)
            openTool("Repeats", in: app)
            XCTAssertTrue(startNewRow.exists)
            XCTAssertFalse(startNewRow.isEnabled, "Layout actions stay visible while Repeats owns the chart")
            tapControlEdge(app.buttons["Repeat This Measure"], at: 0.94)
            XCTAssertTrue(app.buttons["Remove Repeat"].isEnabled)
            app.buttons["Measures"].tap()
            waitForContext("Measure \(target) selected", in: app)

            let confirmation = app.alerts["Delete Measure?"]
            tapControlEdge(deleteMeasure, at: 0.94)
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            XCTAssertTrue(confirmation.staticTexts.containing(NSPredicate(
                format: "label CONTAINS[c] %@", "measure \(target)"
            )).firstMatch.exists, "The confirmation identifies the exact selected measure")
            confirmation.buttons["Cancel"].tap()
            waitForRemoval(confirmation, message: "Cancel leaves the targeted measure intact")
            waitForContext("Measure \(target) selected", in: app)
            openTool("Repeats", in: app)
            XCTAssertTrue(app.buttons["Remove Repeat"].isEnabled, "Cancel preserves the selected measure's repeat")
            app.buttons["Measures"].tap()
            waitForContext("Measure \(target) selected", in: app)

            tapControlEdge(deleteMeasure, at: 0.94)
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            confirmation.buttons["Delete Measure"].tap()
            waitForRemoval(confirmation, message: "Confirming deletes the targeted measure")
            openTool("Repeats", in: app)
            XCTAssertFalse(app.buttons["Remove Repeat"].isEnabled, "The neighboring measure has no repeat")
            tapFirstRow(at: 0.47, in: app)
            XCTAssertFalse(app.buttons["Remove Repeat"].isEnabled, "The deleted measure's repeat is gone")
            attach(app, name: "\(title) direct Measures at \(narrow ? "360 points" : "standard width")")
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
            waitForPurpose("Change the meter from a measure", in: app)
            let threeFour = app.buttons["editor-time-signature-3-4"]
            XCTAssertTrue(threeFour.waitForExistence(timeout: 5), "Meter choices open above the chart")
            retargetFirstRowMeasure(first, at: 0.18, in: app)
            XCTAssertTrue(threeFour.isHittable)
            XCTAssertFalse(app.navigationBars["Apply 3/4"].exists, "Changing the target leaves scope unopened")

            retargetFirstRowMeasure(later, at: 0.47, in: app)
            tapControlEdge(threeFour, at: 0.94)
            let scope = app.navigationBars["Apply 3/4"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            scope.buttons["Cancel"].tap()
            waitForRemoval(scope, message: "Cancel closes the scope sheet and releases canvas input")

            retargetFirstRowMeasure(first, at: 0.18, in: app)
            XCTAssertTrue(threeFour.isHittable, "The canvas remains usable after dismissing scope")
            attach(app, name: "\(title) Measures range and meter scope cancel without locking selection")
            exitChart(in: app)
        }
    }

    @MainActor
    func testCustomTimeSignatureAppliesToTheSelectedMeasureInBothChartStyles() throws {
        let app = try fixtureApplication(narrow: true)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            openTool("Time Signature", in: app)
            waitForPurpose("Change the meter from a measure", in: app)
            tapFirstRow(at: 0.47, in: app)
            let measure = try selectedMeasure(in: app)
            XCTAssertGreaterThan(measure, 1, "Apply a meter change within the chart")

            let custom = app.buttons["editor-time-signature-custom"]
            XCTAssertTrue(custom.waitForExistence(timeout: 5))
            tapControlEdge(custom, at: 0.94)
            let customBar = app.navigationBars["Custom Time Signature"]
            XCTAssertTrue(customBar.waitForExistence(timeout: 5))
            let increase = app.buttons["editor-custom-meter-increase"]
            let eight = app.buttons["editor-custom-meter-denominator-8"]
            XCTAssertTrue(increase.isHittable)
            for _ in 0..<7 { increase.tap() }
            eight.tap()
            XCTAssertTrue(eight.isSelected)
            app.buttons["editor-custom-meter-continue"].tap()

            let scope = app.navigationBars["Apply 11/8"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            waitForRemoval(customBar, message: "The custom editor advances to the apply scope")
            app.buttons["To end of piece"].tap()
            waitForRemoval(scope, message: "Applying a custom meter returns to the chart")
            waitForContext("Measure \(measure) selected", in: app)
            XCTAssertTrue(custom.isHittable, "The sidebar tool remains active after applying the meter")
            tapControlEdge(custom, at: 0.94)
            XCTAssertTrue(customBar.waitForExistence(timeout: 5))
            XCTAssertTrue(eight.isSelected, "The selected measure supplies its saved custom denominator")
            app.buttons["editor-custom-meter-continue"].tap()
            XCTAssertTrue(scope.waitForExistence(timeout: 5), "The selected measure supplies its saved 11/8")
            scope.buttons["Cancel"].tap()
            waitForRemoval(scope, message: "Cancel leaves the applied meter saved")
            attach(app, name: "\(title) custom time signature applies from the visible selected measure")
            exitChart(in: app)
        }
    }

    @MainActor
    func testInlineFormMarkerPlacementInBothChartStyles() throws {
        let app = try fixtureApplication(narrow: true)
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            openTool("Form Markers", in: app)
            waitForPurpose("Place a form marker", in: app)
            tapFirstRow(at: 0.18, in: app)
            let first = try selectedMeasure(in: app)
            let segno = app.buttons["form-marker-option-segno"]
            XCTAssertTrue(segno.waitForExistence(timeout: 5))
            XCTAssertTrue(segno.isHittable, "The Segno choice is a direct top action at narrow width")
            XCTAssertGreaterThanOrEqual(segno.frame.height + 0.5, 44)
            XCTAssertFalse(app.navigationBars["Form Markers"].exists)
            app.buttons["Done"].tap()
            waitForPurpose("Edit items on the chart", in: app)
            waitForRemoval(segno, message: "Done dismisses the form options without adding a marker")
            XCTAssertFalse(app.staticTexts["Marker"].exists)

            openTool("Form Markers", in: app)
            tapFirstRow(at: 0.47, in: app)
            let later = try waitForDifferentSelectedMeasure(than: first, in: app)
            XCTAssertGreaterThan(later, first, "The marker uses the latest chart destination")
            tapControlEdge(segno, at: 0.94)
            waitForRemoval(segno, message: "The direct choice applies and returns to Select")
            waitForPurpose("Edit items on the chart", in: app)
            waitForContext("Measure \(later) selected", in: app)
            XCTAssertTrue(app.staticTexts["Marker"].exists, "The added marker is selected for editing")
            for action in ["Larger", "Smaller", "Delete"] {
                XCTAssertTrue(app.buttons[action].isHittable, action)
            }
            attach(app, name: "\(title) direct Segno placement at the selected measure")
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
        try assertRowMovesFit(narrow: false)
    }

    @MainActor
    func testRowMovesFitNarrowWindowsInBothChartStyles() throws {
        try assertRowMovesFit(narrow: true)
    }

    @MainActor
    private func assertRowMovesFit(narrow: Bool) throws {
        let app = try fixtureApplication(narrow: narrow)
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
            attach(app, name: "\(title) row fits after moving measures in both directions at \(narrow ? "narrow" : "standard") width")
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

        // Grow the first row with the direct tool. The final canvas tap
        // checks placement instead of relying on automatic selection.
        let insert = app.buttons["Add One After"]
        XCTAssertTrue(insert.waitForExistence(timeout: 5))
        for measure in 2...9 {
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
    private func assertLayoutActionsVisible(narrow: Bool, canvas: CGRect, in app: XCUIApplication) {
        for id in layoutActionIDs {
            let action = app.buttons["measure-layout-action-\(id)"]
            XCTAssertTrue(action.exists, "\(id) remains visible")
            if action.isEnabled { XCTAssertTrue(action.isHittable, id) }
            XCTAssertGreaterThanOrEqual(action.frame.height, 44, id)
            XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(action.frame), id)
            if narrow {
                XCTAssertLessThanOrEqual(action.frame.maxY, canvas.minY + 1, id)
            } else {
                XCTAssertLessThanOrEqual(action.frame.maxX, canvas.minX + 1, id)
            }
        }
    }

    @MainActor
    private func assertLayoutActionsDisabled(in app: XCUIApplication) {
        for id in layoutActionIDs {
            let action = app.buttons["measure-layout-action-\(id)"]
            XCTAssertTrue(action.exists)
            XCTAssertFalse(action.isEnabled, "\(id) requires an eligible measure in Select or Measures")
        }
    }

    @MainActor
    private func chooseLayoutAction(_ id: String, in app: XCUIApplication) {
        let action = app.buttons["measure-layout-action-\(id)"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled, "Layout must accept \(id) for this selection")
        tapControlEdge(action, at: 0.94)
        XCTAssertTrue(action.exists, "Editing layout keeps the Layout actions available")
        XCTAssertFalse(app.navigationBars["Measure Layout"].exists)
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
        XCTAssertTrue(app.buttons["Repeats"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func exitChart(in app: XCUIApplication) {
        app.buttons["Exit Chart"].tap()
        XCTAssertTrue(app.buttons["Select charts"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openTool(_ title: String, in app: XCUIApplication) {
        let id: String
        switch title {
        case "Repeats": id = "Repeats"
        case "Time Signature": id = "editor-sidebar-time-signature"
        case "Text": id = "editor-sidebar-text"
        case "Form Markers": id = "editor-sidebar-form-markers"
        default:
            XCTFail("Unrecognized editor test destination: \(title)")
            return
        }
        let entry = app.buttons[id]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        tapControlEdge(entry, at: 0.94)
    }

    @MainActor
    private func topRepeatAction(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", title,
            "editor-sidebar-repeat")).firstMatch
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
    private func retargetFirstRowMeasure(_ measure: Int, at horizontalFraction: CGFloat, in app: XCUIApplication) {
        // Opening a taller tool keeps the paper's prior scroll anchor.
        // Try the same measure across the possible first-system positions.
        for documentY: CGFloat in [250, 200, 150, 300, 350] {
            tapFirstRow(at: horizontalFraction, documentY: documentY, in: app)
            if (try? selectedMeasure(in: app)) == measure { break }
        }
        waitForContext("Measure \(measure) selected", in: app)
    }

    @MainActor
    private func tapFirstRow(at horizontalFraction: CGFloat, documentY: CGFloat = 250, in app: XCUIApplication) {
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
            y: frame.minY + verticalInset + documentY * fitScale)
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
