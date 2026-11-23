import XCTest

/// Uses normal tool menus and real canvas taps in a separate process. These
/// fixtures contain no user charts; no private canvas action is invoked.
final class ToolMeasureSelectionUITests: XCTestCase {
    private let fixtureTitles = ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"]

    override func setUpWithError() throws {
        continueAfterFailure = false
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
    func testRepeatStartAndEndRemainSelectableInBothChartStyles() throws {
        let app = try fixtureApplication()
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

            tapControlEdge(app.buttons["Repeat Measures"], at: 0.94)
            let startRepeat = app.buttons["Start Repeat"]
            XCTAssertTrue(startRepeat.waitForExistence(timeout: 5))
            startRepeat.tap()
            waitForContext("Start: measure \(start) · Current end: measure \(start)", in: app)
            XCTAssertTrue(app.buttons["End Repeat"].isHittable)

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
            insert.tap()
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
    private func fixtureApplication() throws -> XCUIApplication {
        #if targetEnvironment(simulator)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-iChartEditorUIPreview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-iChartChartPreviewMode", "collapsed", "-iChartChartsWorkspaceMode", "charts",
            "-iChartHasSeenAccountLanding", "NO", "-iChartHasSeenGuidedTourOffer", "YES"
        ]
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
        let entry = app.buttons[title]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
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
        XCTAssertTrue(app.windows.firstMatch.frame.contains(point))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
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
