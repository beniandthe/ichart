import XCTest

/// Exercises the real row Menu and confirmation presenter, rather than calling
/// the deletion store directly. Only disposable Simulator fixtures are used.
final class LibraryConsecutiveDeletionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConsecutiveRowMenuDeletesWithoutOpeningAChart() throws {
        let app = try fixtureApplication()
        app.launch()

        let firstTitle = "Rhythm Section UI Fixture"
        let nextTitle = "Simple Sheet UI Fixture"
        let first = chartButton(firstTitle, in: app)
        let next = chartButton(nextTitle, in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertLessThan(first.frame.midY, next.frame.midY,
            "The second target starts below the first in the recent-chart list")

        try requestDeletion(firstTitle, in: app)
        app.alerts["Delete Chart?"].buttons["Delete"].tap()
        waitForRemoval(first, message: "The first confirmed chart leaves the library")
        XCTAssertTrue(next.exists, "Deleting the first row must keep the next chart")
        XCTAssertFalse(app.buttons["Exit Chart"].exists)

        // No navigation, relaunch, selection-mode toggle, or other reset between
        // requests: the next row's menu must present a fresh confirmation.
        try requestDeletion(nextTitle, in: app)
        app.alerts["Delete Chart?"].buttons["Delete"].tap()
        waitForRemoval(next, message: "The next confirmed chart also leaves the library")
        XCTAssertFalse(app.buttons["Exit Chart"].exists)
        XCTAssertGreaterThan(app.buttons.matching(identifier: "Chart actions").count, 0,
            "The unrelated sample chart remains available")
        attach(app, name: "Two consecutive chart-menu deletions without navigation")
    }

    @MainActor
    func testCancelAfterFirstDeletionAllowsTheSameNextChartToBeRequestedAgain() throws {
        let app = try fixtureApplication()
        app.launch()
        let first = chartButton("Rhythm Section UI Fixture", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        try requestDeletion("Rhythm Section UI Fixture", in: app)
        app.alerts["Delete Chart?"].buttons["Delete"].tap()
        waitForRemoval(first, message: "The first confirmed chart leaves the library")

        let remaining = chartButton("Simple Sheet UI Fixture", in: app)
        try requestDeletion("Simple Sheet UI Fixture", in: app)
        app.alerts["Delete Chart?"].buttons["Cancel"].tap()
        waitForRemoval(app.alerts["Delete Chart?"], message: "Cancel dismisses the confirmation")
        XCTAssertTrue(remaining.exists, "Cancel must retain the requested chart")

        try requestDeletion("Simple Sheet UI Fixture", in: app)
        app.alerts["Delete Chart?"].buttons["Delete"].tap()
        waitForRemoval(remaining, message: "A new request after Cancel deletes the exact chart")
        XCTAssertFalse(app.buttons["Exit Chart"].exists)
        attach(app, name: "Cancel and re-request after an earlier chart deletion")
    }

    @MainActor
    func testConsecutiveMenuDeletesAfterReturningFromChartWithLargePreviewsInLandscape() throws {
        let app = try fixtureApplication(previewMode: "large")
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let rhythm = chartButton("Rhythm Section UI Fixture", in: app)
        XCTAssertTrue(rhythm.waitForExistence(timeout: 20))
        rhythm.tap()
        let exit = app.buttons["Exit Chart"]
        XCTAssertTrue(exit.waitForExistence(timeout: 15))
        exit.tap()
        XCTAssertTrue(rhythm.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["Large preview"].value as? String, "Selected")

        // This entry state matches a working chart session followed by cleanup.
        // Ordinary scrolling is allowed; no chart opens between the deletions.
        for title in ["Rhythm Section UI Fixture", "Simple Sheet UI Fixture", "Turnaround Study"] {
            let target = chartButton(title, in: app)
            try requestDeletion(title, in: app)
            app.alerts["Delete Chart?"].buttons["Delete"].tap()
            waitForRemoval(target, message: "The confirmed chart disappears after returning from an editor")
            XCTAssertFalse(app.buttons["Exit Chart"].exists)
        }
        XCTAssertTrue(app.staticTexts["No Charts Yet"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Chart actions").count, 0)
        attach(app, name: "All three charts deleted after editor return in landscape with Large previews")
    }

    @MainActor
    func testBulkCancelAndConfirmDeleteOnlyTheTwoSelectedCharts() throws {
        let app = try fixtureApplication()
        app.launch()
        let select = app.buttons["Select charts"]
        XCTAssertTrue(select.waitForExistence(timeout: 20))
        select.tap()
        let selectedTitles = ["Rhythm Section UI Fixture", "Simple Sheet UI Fixture"]
        for title in selectedTitles {
            let row = app.buttons[title]
            XCTAssertTrue(row.exists)
            row.tap()
            XCTAssertEqual(row.value as? String, "Selected")
        }
        XCTAssertEqual(app.buttons["Turnaround Study"].value as? String, "Not selected")
        let deleteSelection = app.buttons["Delete 2 selected charts shown in results"]
        XCTAssertTrue(deleteSelection.exists)
        deleteSelection.tap()
        let confirmation = app.alerts["Delete 2 Charts?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        for title in selectedTitles {
            XCTAssertTrue(confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists)
        }
        XCTAssertFalse(confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Turnaround Study")).firstMatch.exists)
        confirmation.buttons["Cancel"].tap()
        waitForRemoval(confirmation, message: "Cancel dismisses the bulk confirmation")
        for title in selectedTitles {
            XCTAssertEqual(app.buttons[title].value as? String, "Selected",
                "Cancel retains both chart data and the exact selection")
        }
        XCTAssertTrue(app.buttons["Turnaround Study"].exists)

        deleteSelection.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete 2"].tap()
        for title in selectedTitles {
            waitForRemoval(chartButton(title, in: app), message: "Only an explicitly selected chart is deleted")
        }
        XCTAssertTrue(chartButton("Turnaround Study", in: app).exists,
            "The unselected sample is retained")
        try requestDeletion("Turnaround Study", in: app)
        app.alerts["Delete Chart?"].buttons["Cancel"].tap()
        waitForRemoval(app.alerts["Delete Chart?"], message: "The remaining chart's fresh menu confirmation dismisses")
        XCTAssertTrue(chartButton("Turnaround Study", in: app).exists)
        attach(app, name: "Bulk cancellation and exact selection deletion preserve the unselected chart")
    }

    @MainActor
    private func fixtureApplication(previewMode: String = "collapsed") throws -> XCUIApplication {
        #if targetEnvironment(simulator)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-iChartEditorUIPreview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-iChartChartPreviewMode", previewMode, "-iChartChartsWorkspaceMode", "charts",
            "-iChartHasSeenAccountLanding", "NO", "-iChartHasSeenGuidedTourOffer", "YES"
        ]
        return app
        #else
        throw XCTSkip("Chart deletion regression uses disposable Simulator fixtures only.")
        #endif
    }

    @MainActor
    private func chartButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    @MainActor
    private func requestDeletion(_ title: String, in app: XCUIApplication) throws {
        let row = chartButton(title, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The exact target chart is listed")
        // Large previews can put a row's centered menu below the viewport even
        // while the top of its open-chart button is already visible.
        for _ in 0..<7 {
            let candidate = app.buttons.matching(identifier: "Chart actions").allElementsBoundByIndex.min(by: {
                abs($0.frame.midY - row.frame.midY) < abs($1.frame.midY - row.frame.midY)
            })
            if let candidate, candidate.isHittable,
               abs(candidate.frame.midY - row.frame.midY) < row.frame.height / 2 + 2 { break }
            let scroll = app.scrollViews.firstMatch
            XCTAssertTrue(scroll.exists, "The chart library exposes its normal scrolling surface")
            scroll.swipeUp()
        }
        let actions = app.buttons.matching(identifier: "Chart actions").allElementsBoundByIndex
        let menu = try XCTUnwrap(actions.min(by: {
            abs($0.frame.midY - row.frame.midY) < abs($1.frame.midY - row.frame.midY)
        }), "Each chart row exposes its three-dot Chart actions menu")
        XCTAssertLessThan(abs(menu.frame.midY - row.frame.midY), row.frame.height / 2 + 2,
            "The menu must belong to the requested chart row")
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "The three-dot menu offers Delete")
        delete.tap()

        let alert = app.alerts["Delete Chart?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
            "Every row-menu Delete opens a new confirmation without leaving the chart list")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists,
            "The confirmation names the exact requested chart, not a previously deleted row")
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
