import XCTest

/// Uses the app's normal controls from a separate UI-test process. Both
/// disposable fixtures remain saved for independent container readback.
final class FormMarkerPlacementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExplainersAcrossLayoutsAndRenderingModes() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-iChartEditorUIPreview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        func assertReadable(_ element: XCUIElement, name: String) {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(name) must exist in the external accessibility tree")
            XCTAssertFalse(element.label.isEmpty, "\(name) must contain readable text")
            XCTAssertTrue(element.isHittable, "\(name) must be visible in the current viewport")
            XCTAssertGreaterThan(element.frame.width, 0)
            XCTAssertGreaterThan(element.frame.height, 0)
            XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(element.frame),
                "\(name) must fit inside the app window: \(element.frame)")
        }

        for title in ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"] {
            let chart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 20))
            chart.tap()
            let writingTool = app.buttons["Write & Render"]
            XCTAssertTrue(writingTool.waitForExistence(timeout: 15))
            writingTool.tap()

            for mode in ["Automatic", "Manual"] {
                let modeMenu = app.descendants(matching: .any).matching(identifier: "editor-rendering-mode").firstMatch
                XCTAssertTrue(modeMenu.waitForExistence(timeout: 10))
                XCTAssertTrue(modeMenu.isHittable)
                modeMenu.tap()
                let choice = mode == "Automatic"
                    ? "Automatic — render after a pause"
                    : "Manual — check previews, then render"
                let option = app.buttons[choice]
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()

                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "\(title) \(mode) external accessibility tree"
                tree.lifetime = .keepAlways
                add(tree)

                let purpose = app.staticTexts["editor-guidance-purpose"]
                let firstStep = app.staticTexts["editor-guidance-step-1"]
                let secondStep = app.staticTexts["editor-guidance-step-2"]
                let context = app.staticTexts["editor-guidance-context"]
                assertReadable(purpose, name: "Purpose")
                assertReadable(firstStep, name: "First writing step")
                assertReadable(secondStep, name: "Second writing step")
                assertReadable(context, name: "Rendering context")
                XCTAssertEqual(purpose.label, "Turn handwriting into chart notation")
                XCTAssertEqual(context.label, "Rendering: \(mode)")
                XCTAssertTrue(firstStep.label.contains("Apple Pencil"))
                XCTAssertTrue(secondStep.label.contains(mode == "Automatic" ? "pause" : "Render Chords"))
                XCTAssertLessThan(purpose.frame.minY, firstStep.frame.maxY)
                XCTAssertLessThanOrEqual(firstStep.frame.minY, secondStep.frame.minY)
                for label in ["Write", "Erase", "Done"] {
                    let control = app.buttons[label]
                    XCTAssertTrue(control.waitForExistence(timeout: 5))
                    XCTAssertTrue(control.isHittable, "\(label) must remain reachable below the helper")
                    XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(control.frame))
                }
                XCTAssertTrue(writingTool.isSelected)

                let guide = app.buttons["Write & Render guide"]
                XCTAssertTrue(guide.isHittable)
                guide.tap()
                let guideBar = app.navigationBars["Write & Render guide"]
                XCTAssertTrue(guideBar.waitForExistence(timeout: 10))
                let done = guideBar.buttons["Done"]
                XCTAssertTrue(done.isHittable)
                done.tap()
                XCTAssertTrue(writingTool.waitForExistence(timeout: 10))
                XCTAssertTrue(writingTool.isSelected, "Closing the Guide returns to Write & Render")
                XCTAssertTrue(firstStep.waitForExistence(timeout: 5))
                XCTAssertTrue(secondStep.waitForExistence(timeout: 5))
                attach(app, name: "\(title) \(mode) two-step helper and reachable controls")
            }
            app.buttons["Exit Chart"].tap()
            XCTAssertTrue(chart.waitForExistence(timeout: 10))
        }
    }

    @MainActor
    func testFormMarkerPlacementInBothLayouts() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-iChartEditorUIPreview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        for title in ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"] {
            let chart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 20), "The synthetic chart must be available in Charts")
            chart.tap()
            XCTAssertTrue(app.buttons["Tools"].waitForExistence(timeout: 15))

            openMarkers(in: app)
            chooseMeasureTwo(in: app)
            chooseSegno(in: app)
            let stagedTarget = app.staticTexts["Add Segno to measure 2"]
            reveal(stagedTarget, in: app)
            XCTAssertTrue(stagedTarget.isHittable, "The exact destination is visible before confirmation")
            attach(app, name: "\(title) staged Segno at measure 2 before Cancel")
            app.navigationBars["Form Markers"].buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["Tools"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Marker"].exists, "Cancel must not add a marker")

            openMarkers(in: app)
            let coda = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Coda")).firstMatch
            reveal(coda, in: app, scrollDown: true)
            XCTAssertTrue(coda.isSelected, "A cancelled Segno selection must not carry into a new placement")
            let defaultTarget = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Add Coda to measure ")).firstMatch
            reveal(defaultTarget, in: app)
            XCTAssertTrue(defaultTarget.isHittable, "The reopened placement shows its default marker and destination")
            chooseMeasureTwo(in: app)
            chooseSegno(in: app)
            let confirmedTarget = app.staticTexts["Add Segno to measure 2"]
            reveal(confirmedTarget, in: app)
            XCTAssertTrue(confirmedTarget.isHittable)
            attach(app, name: "\(title) confirmed target before Add")
            app.navigationBars["Form Markers"].buttons["Add"].tap()

            let markerTray = app.staticTexts["Marker"]
            XCTAssertTrue(markerTray.waitForExistence(timeout: 10), "The newly added marker is selected for editing")
            XCTAssertTrue(app.staticTexts["Measure 2 selected"].exists,
                "The selection context must match the exact measure confirmed in the sheet")
            XCTAssertTrue(app.buttons["Larger"].exists)
            XCTAssertTrue(app.buttons["Smaller"].exists)
            XCTAssertTrue(app.buttons["Delete"].exists)
            attach(app, name: "\(title) Segno added with Measure 2 context")
            app.buttons["Exit Chart"].tap()
            XCTAssertTrue(chart.waitForExistence(timeout: 10))
        }
    }

    @MainActor
    private func openMarkers(in app: XCUIApplication) {
        app.buttons["Tools"].tap()
        let entry = app.buttons["Form Markers"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.navigationBars["Form Markers"].waitForExistence(timeout: 10))
        let instruction = app.staticTexts["Choose a measure and a marker, then tap Add. Nothing changes until you add it."]
        XCTAssertTrue(instruction.waitForExistence(timeout: 5))
    }

    @MainActor
    private func chooseMeasureTwo(in app: XCUIApplication) {
        let picker = app.descendants(matching: .any).matching(identifier: "form-marker-measure").firstMatch
        reveal(picker, in: app, scrollDown: true)
        picker.tap()
        let secondMeasure = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Measure 2")).firstMatch
        XCTAssertTrue(secondMeasure.waitForExistence(timeout: 5))
        secondMeasure.tap()
    }

    @MainActor
    private func chooseSegno(in app: XCUIApplication) {
        let segno = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Segno")).firstMatch
        reveal(segno, in: app)
        segno.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollDown: Bool = false) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let collection = app.collectionViews.firstMatch
            let table = app.tables.firstMatch
            let scrollSurface = collection.exists ? collection : (table.exists ? table : app)
            if scrollDown { scrollSurface.swipeDown() }
            else { scrollSurface.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable,
            "The requested sheet control must be reachable through ordinary scrolling")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
