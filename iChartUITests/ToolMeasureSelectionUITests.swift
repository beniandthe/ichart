import XCTest

/// Uses normal tool menus and real canvas taps in a separate process. These
/// fixtures contain no user charts; no private canvas action is invoked.
final class ToolMeasureSelectionUITests: XCTestCase {
    private let fixtureTitles = ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"]

    override func setUpWithError() throws {
        continueAfterFailure = false
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

            app.buttons["Repeat Measures"].tap()
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
            app.buttons["End Repeat"].tap()
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

            app.buttons["Delete"].tap()
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
            let initial = try selectedMeasure(in: app)
            let guide = app.buttons["editor-tool-guide-button"]
            XCTAssertTrue(guide.isHittable)
            guide.tap()
            let done = app.buttons["editor-tool-guide-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
            waitForRemoval(done, message: "Done closes the local tool guide")

            tapFirstRow(at: 0.47, in: app)
            let later = try waitForDifferentSelectedMeasure(than: initial, in: app)
            XCTAssertTrue(app.buttons["Above"].isHittable)
            app.buttons["Above"].tap()
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            let entry = app.textViews["editor-cue-text-entry"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            XCTAssertFalse(entry.hasFocus, "Opening Text leaves the cue field idle")
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            let entryFrame = entry.frame
            let startScribble = app.buttons["Start Scribble for Cue text"]
            XCTAssertTrue(startScribble.isHittable)
            startScribble.tap()
            XCTAssertFalse(entry.hasFocus, "Preparing for Scribble must leave the field idle")
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            XCTAssertEqual(entry.frame, entryFrame)
            let keyboard = app.buttons["Use keyboard for Cue text"]
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
            app.buttons["Below"].tap()
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
        app.buttons["Tools"].tap()
        let entry = app.buttons[title]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts["editor-guidance-context"].waitForExistence(timeout: 5))
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
