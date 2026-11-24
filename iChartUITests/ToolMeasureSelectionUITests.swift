import UIKit
import XCTest

/// Uses normal tool menus and real canvas taps in a separate process. These
/// fixtures contain no user charts; no private canvas action is invoked.
final class ToolMeasureSelectionUITests: XCTestCase {
    private let fixtureTitles = ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuickMeasureAndRepeatActionsInPortraitAcrossBothStyles() throws {
        try assertQuickMeasureAndRepeatActions(orientation: .portrait)
    }

    @MainActor
    func testQuickMeasureAndRepeatActionsInLandscapeAcrossBothStyles() throws {
        try assertQuickMeasureAndRepeatActions(orientation: .landscapeLeft)
    }

    @MainActor
    private func assertQuickMeasureAndRepeatActions(orientation: UIDeviceOrientation) throws {
        let app = try fixtureApplication(narrow: false)
        if orientation.isLandscape {
            app.launchArguments.append("-iChartEditorUILandscape")
        }
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let window = app.windows.firstMatch
        let expectedOrientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard window.exists else { return false }
            let size = window.frame.size
            return orientation.isLandscape ? size.width > size.height : size.height > size.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectedOrientation], timeout: 10), .completed,
            "The app window must match the requested orientation before testing the gutter")
        for title in fixtureTitles {
            openFixture(title, in: app)
            let size = window.frame.size
            XCTAssertEqual(size.width > size.height, orientation.isLandscape)
            let group = app.descendants(matching: .any).matching(identifier: "editor-quick-actions").firstMatch
            let measures = app.buttons["editor-tool-measures"]
            let toolButtons = railTools(in: app)
            let start = app.buttons["editor-quick-start-repeat"]
            let end = app.buttons["editor-quick-end-repeat"]
            let cancel = app.buttons["editor-quick-cancel-repeat"]
            XCTAssertTrue(group.waitForExistence(timeout: 5))
            XCTAssertTrue(measures.isHittable)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Measures")).count, 1,
                "The wide editor keeps Measures in its existing top location")
            XCTAssertFalse(app.buttons["editor-quick-measures"].exists)
            XCTAssertFalse(app.buttons["Tools"].exists)
            XCTAssertFalse(start.exists, "Select must not offer a repeat destination before a real measure tap")
            let originalViewport = try assertQuickActionsOutsideCanvas(group, buttons: toolButtons, in: app)

            tapFirstRow(at: 0.18, in: app)
            let first = try selectedMeasure(in: app)
            XCTAssertTrue(start.isEnabled)
            tapFirstRow(at: 0.47, in: app)
            let last = try waitForDifferentSelectedMeasure(than: first, in: app)
            XCTAssertLessThan(first, last)
            tapFirstRow(at: 0.18, in: app)
            waitForContext("Measure \(first) selected", in: app)
            tapControlEdge(measures, at: 0.92)
            waitForPurpose("Change measures and rows", in: app)
            XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["measure-layout-open"].isHittable)
            XCTAssertTrue(app.buttons["Delete"].isHittable)
            waitForContext("Measure \(first) selected", in: app)

            tapControlEdge(start, at: 0.92)
            waitForPurpose("Repeat measures or add an ending", in: app)
            waitForContext("Start: measure \(first) · Current end: measure \(first)", in: app)
            XCTAssertTrue(end.waitForExistence(timeout: 5))
            XCTAssertTrue(end.isHittable)
            XCTAssertTrue(cancel.isHittable)
            XCTAssertFalse(start.exists)
            let pendingViewport = try assertQuickActionsOutsideCanvas(group, buttons: toolButtons + [end, cancel], in: app)
            XCTAssertEqual(pendingViewport.minX, originalViewport.minX, accuracy: 1)
            XCTAssertEqual(pendingViewport.width, originalViewport.width, accuracy: 1)
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: measure \(first) · Current end: measure \(last)", in: app)
            tapControlEdge(cancel, at: 0.92)
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            XCTAssertTrue(start.isEnabled)
            XCTAssertFalse(end.exists)
            XCTAssertFalse(cancel.exists)
            XCTAssertTrue(measures.isEnabled)
            XCTAssertTrue(toolButtons.allSatisfy(\.isEnabled))
            waitForPurpose("Repeat measures or add an ending", in: app)
            waitForContext("Measure \(last) selected", in: app)
            assertRepeatRemovalIsEnabled(false, in: app)
            tapFirstRow(at: 0.18, in: app)
            waitForContext("Measure \(first) selected", in: app)
            assertRepeatRemovalIsEnabled(false, in: app)

            tapControlEdge(start, at: 0.08)
            waitForContext("Start: measure \(first) · Current end: measure \(first)", in: app)
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: measure \(first) · Current end: measure \(last)", in: app)
            tapControlEdge(end, at: 0.08)
            waitForContext("Measure \(last) selected", in: app)
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            XCTAssertFalse(end.exists)
            XCTAssertFalse(cancel.exists)
            XCTAssertTrue(measures.isEnabled)
            assertRepeatRemovalIsEnabled(true, in: app)
            app.buttons["Select"].tap()
            XCTAssertTrue(group.waitForExistence(timeout: 5))
            _ = try assertQuickActionsOutsideCanvas(group, buttons: toolButtons + [start], in: app)
            app.buttons["Write & Render"].tap()
            XCTAssertTrue(app.buttons["editor-rendering-mode"].waitForExistence(timeout: 5))
            XCTAssertTrue(group.exists, "The left tool destinations remain reachable while writing")
            _ = try assertQuickActionsOutsideCanvas(group, buttons: toolButtons, in: app)
            for identifier in ["editor-quick-measures", "editor-quick-start-repeat",
                "editor-quick-end-repeat", "editor-quick-cancel-repeat"] {
                XCTAssertFalse(app.buttons[identifier].exists)
            }
            app.buttons["Select"].tap()
            XCTAssertTrue(group.waitForExistence(timeout: 5))
            XCTAssertFalse(start.exists, "Returning from writing must not invent a selected measure")
            _ = try assertQuickActionsOutsideCanvas(group, buttons: toolButtons, in: app)
            tapFirstRow(at: 0.18, in: app)
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            _ = try assertQuickActionsOutsideCanvas(group, buttons: toolButtons + [start], in: app)
            if orientation == .portrait {
                let viewport = try quickActionDocumentViewport(in: app)
                viewport.pinch(withScale: 1.25, velocity: 1)
                viewport.swipeUp(velocity: .slow)
                _ = try assertQuickActionsOutsideCanvas(group, buttons: toolButtons + [start], in: app)
                tapControlEdge(measures, at: 0.92)
                waitForPurpose("Change measures and rows", in: app)
            }
            attach(app, name: "\(title) quick action gutter \(orientation.rawValue)")
            exitChart(in: app)
        }
    }

    @MainActor
    private func quickActionDocumentViewport(in app: XCUIApplication) throws -> XCUIElement {
        try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.filter {
            $0.isHittable && $0.frame.width > app.windows.firstMatch.frame.width * 0.7 && $0.frame.height > 200
        }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    }

    @MainActor
    @discardableResult
    private func assertQuickActionsOutsideCanvas(_ group: XCUIElement, buttons: [XCUIElement],
        in app: XCUIApplication) throws -> CGRect {
        let viewport = try quickActionDocumentViewport(in: app)
        XCTAssertFalse(group.frame.isEmpty)
        XCTAssertLessThanOrEqual(group.frame.width, 80)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(group.frame))
        XCTAssertLessThanOrEqual(group.frame.maxX, viewport.frame.minX + 1,
            "The tool rail sits to the left of the writing canvas")
        // A landscape scene can be fitted into a portrait Simulator display.
        // Its full-width rail supplies the scale from app points to screen points.
        let screenScale = min(1, group.frame.width / 72)
        for button in buttons {
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height + 0.5, 44 * screenScale)
            XCTAssertTrue(group.frame.insetBy(dx: -1, dy: -1).contains(button.frame))
            XCTAssertFalse(button.frame.intersects(viewport.frame))
        }
        return viewport.frame
    }

    @MainActor
    private func assertRepeatRemovalIsEnabled(_ expected: Bool, in app: XCUIApplication) {
        app.buttons["Manage"].tap()
        let remove = app.buttons["Remove Repeat"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertEqual(remove.isEnabled, expected,
            expected ? "End Repeat must commit the targeted range" : "Cancel must leave no repeat at either endpoint")
        dismissOpenMenu(in: app)
        waitForRemoval(remove, message: "Inspecting repeat availability leaves the current tool usable")
    }

    @MainActor
    func testLeftToolRailOpensEveryDestinationFromItsVisibleEdgesInBothStyles() throws {
        let app = try fixtureApplication(narrow: false)
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
            let group = app.descendants(matching: .any).matching(identifier: "editor-quick-actions").firstMatch
            XCTAssertTrue(group.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Tools"].exists)
            XCTAssertFalse(app.buttons["editor-quick-start-repeat"].exists)
            _ = try assertQuickActionsOutsideCanvas(group, buttons: railTools(in: app), in: app)
            for (index, destination) in destinations.enumerated() {
                let entry = railTool(destination.title, in: app)
                XCTAssertTrue(entry.isEnabled)
                tapControlEdge(entry, at: index.isMultiple(of: 2) ? 0.94 : 0.06)
                if destination.title == "Form Markers" {
                    let sheet = app.navigationBars["Form Markers"]
                    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
                    XCTAssertTrue(app.staticTexts["form-marker-instruction"].exists)
                    sheet.buttons["Cancel"].tap()
                    waitForRemoval(sheet, message: "Cancel returns to the chart without adding a marker")
                    XCTAssertFalse(app.staticTexts["Marker"].exists)
                } else {
                    waitForPurpose(destination.purpose, in: app)
                    XCTAssertTrue(entry.isSelected, "The rail identifies the active tool")
                    if destination.title == "Repeats" {
                        XCTAssertTrue(app.buttons["Repeat Measures"].isHittable)
                        XCTAssertTrue(app.buttons["Add Ending"].isHittable)
                    } else if destination.title == "Text" {
                        tapFirstRow(at: 0.18, in: app)
                        XCTAssertTrue(app.buttons["Above"].waitForExistence(timeout: 5))
                        XCTAssertTrue(app.buttons["Below"].isHittable)
                    }
                }
                XCTAssertFalse(app.buttons["Tools"].exists)
                XCTAssertFalse(app.textViews["editor-cue-text-entry"].exists)
                XCTAssertFalse(app.keyboards.firstMatch.exists,
                    "A tool destination must not implicitly begin text input")
                _ = try assertQuickActionsOutsideCanvas(group, buttons: railTools(in: app), in: app)
            }
            attach(app, name: "\(title) wide left tool rail reaches every destination")
            exitChart(in: app)
        }
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
            XCTAssertTrue(app.buttons["Tools"].isHittable)
            XCTAssertTrue(railTools(in: app).allSatisfy { !$0.exists },
                "A narrow editor uses the Tools dropdown instead of the left rail")
            XCTAssertLessThanOrEqual(try quickActionDocumentViewport(in: app).frame.width, 620)
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
                        XCTAssertTrue(app.buttons["Repeat Measures"].waitForExistence(timeout: 5))
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
        let app = try fixtureApplication()
        app.launch()
        defer { app.terminate() }
        for title in fixtureTitles {
            openFixture(title, in: app)
            XCTAssertFalse(app.buttons["editor-quick-start-repeat"].exists)
            openTool("Repeats", in: app)

            let initial = try selectedMeasure(in: app)
            XCTAssertTrue(app.buttons["editor-quick-start-repeat"].isHittable)
            XCTAssertTrue(railTools(in: app).allSatisfy { !$0.exists })
            tapFirstRow(at: 0.47, in: app)
            let end = try waitForDifferentSelectedMeasure(than: initial, in: app)
            tapFirstRow(at: 0.18, in: app)
            let start = try waitForDifferentSelectedMeasure(than: end, in: app)
            XCTAssertLessThan(start, end)

            tapControlEdge(app.buttons["Repeat Measures"], at: 0.94)
            let startRepeat = app.buttons["Start Repeat"]
            XCTAssertTrue(startRepeat.waitForExistence(timeout: 5))
            tapControlEdge(startRepeat, at: 0.94)
            waitForContext("Start: measure \(start) · Current end: measure \(start)", in: app)
            XCTAssertTrue(app.buttons["End Repeat"].isHittable)
            XCTAssertTrue(app.buttons["editor-quick-end-repeat"].isHittable)
            XCTAssertTrue(app.buttons["editor-quick-cancel-repeat"].isHittable)

            // The pending range must survive this canvas tap. A change to
            // Select or a dropped endpoint is not a successful repeat flow.
            tapFirstRow(at: 0.47, in: app)
            waitForContext("Start: measure \(start) · Current end: measure \(end)", in: app)
            XCTAssertTrue(app.buttons["End Repeat"].isHittable)
            tapControlEdge(app.buttons["End Repeat"], at: 0.06)
            waitForContext("Measure \(end) selected", in: app)
            XCTAssertTrue(app.buttons["Repeat Measures"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["End Repeat"].exists)
            attach(app, name: "\(title) repeat completed from measure \(start) through \(end)")
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
    private func fixtureApplication(narrow: Bool = true) throws -> XCUIApplication {
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
        XCTAssertTrue(app.buttons["Measures"].waitForExistence(timeout: 15))
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
    private func railTool(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let ids = ["Repeats": "repeats", "Time Signature": "timeSignature",
            "Text": "text", "Form Markers": "formMarkers"]
        guard let id = ids[title] else {
            XCTFail("Unrecognized rail test destination: \(title)")
            return app.buttons[title]
        }
        return app.buttons["editor-quick-tool-\(id)"]
    }

    @MainActor
    private func railTools(in app: XCUIApplication) -> [XCUIElement] {
        ["Repeats", "Time Signature", "Text", "Form Markers"].map { railTool($0, in: app) }
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
        tapWindow(at: point, in: app)
    }

    @MainActor
    private func tapFirstRow(at horizontalFraction: CGFloat, in app: XCUIApplication) {
        // The blank fixtures use fixed 932-point paper. Their first system
        // begins at y=186; y=250 lies inside the measure body in both styles.
        // Fit-width zoom maps logical distances by viewport.width / 932.
        // Normal UI taps and the visible selected-measure context validate
        // these coordinates; nothing queries private in-process geometry.
        let candidates = app.scrollViews.allElementsBoundByIndex.filter {
            $0.isHittable && $0.frame.width > app.windows.firstMatch.frame.width * 0.7
                && $0.frame.height > 200
        }
        guard let viewport = candidates.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else {
            XCTFail("The visible document viewport must be available for a normal canvas tap")
            return
        }
        let frame = viewport.frame
        let point = CGPoint(x: frame.minX + frame.width * horizontalFraction,
            y: frame.minY + frame.width * (250.0 / 932.0))
        XCTAssertTrue(frame.contains(point), "The first-row target is visible inside the canvas")
        tapWindow(at: point, in: app)
    }

    @MainActor
    private func tapWindow(at point: CGPoint, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let frame = window.frame
        XCTAssertTrue(frame.contains(point))
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - frame.minX, dy: point.y - frame.minY)).tap()
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
