import XCTest

/// Uses the app's normal controls from a separate UI-test process. Both
/// disposable fixtures remain saved for independent container readback.
final class FormMarkerPlacementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Cold processes are intentional: the first construction must resolve the
    /// toolbar's Swift type metadata rather than reuse a warmed metadata cache.
    /// Run this on a physical iPad as well as Simulator: the device main stack
    /// is smaller and exposed the Build 146 entry crash.
    @MainActor
    func testColdWriteAndRenderEntryAndReentryAcrossLayoutsAndModes() throws {
        XCUIDevice.shared.orientation = .portrait
        #if targetEnvironment(simulator)
        let app = XCUIApplication()
        let fixtureArguments = ["-iChartEditorUIPreview"]
        #else
        let bundleID = ProcessInfo.processInfo.environment["ICHART_ENTRY_TEST_BUNDLE_ID"] ?? ""
        try XCTSkipUnless(bundleID.hasPrefix("com.ichart.claritycrash"),
            "Physical acceptance requires an explicitly selected disposable app with synthetic fixtures.")
        let app = XCUIApplication(bundleIdentifier: bundleID)
        // The disposable app is seeded externally with synthetic normal saved
        // charts. Production app preview gates remain Simulator-only.
        let fixtureArguments: [String] = []
        #endif

        for title in ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"] {
            for manual in [false, true] {
                app.launchArguments = fixtureArguments + [
                    "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                    "-iChartManualRenderWithPreview", manual ? "YES" : "NO"
                ]
                app.launch()
                let chart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
                XCTAssertTrue(chart.waitForExistence(timeout: 20))
                chart.tap()
                let writingTool = app.buttons["Write & Render"]
                XCTAssertTrue(writingTool.waitForExistence(timeout: 15))
                XCTAssertFalse(writingTool.isSelected, "Each cold chart entry starts in Browse")

                for entry in 1...2 {
                    writingTool.tap()
                    let context = app.staticTexts["editor-guidance-context"]
                    XCTAssertTrue(context.waitForExistence(timeout: 10),
                        "Toolbar construction must survive entry \(entry) for \(title), \(manual ? "Manual" : "Automatic")")
                    XCTAssertEqual(app.state, .runningForeground)
                    XCTAssertTrue(writingTool.isSelected)
                    XCTAssertEqual(context.label, "Rendering: \(manual ? "Manual" : "Automatic")")
                    XCTAssertEqual(app.staticTexts["editor-guidance-purpose"].label,
                        "Turn handwriting into chart notation")
                    for label in ["Write", "Erase", "Done"] {
                        let control = app.buttons[label]
                        XCTAssertTrue(control.waitForExistence(timeout: 5))
                        XCTAssertTrue(control.isHittable, "\(label) stays reachable after toolbar construction")
                    }
                    attach(app, name: "\(title) \(manual ? "Manual" : "Automatic") cold entry \(entry)")
                    app.buttons["Done"].tap()
                    let returnedToBrowse = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in !writingTool.isSelected }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [returnedToBrowse], timeout: 5), .completed)
                    XCTAssertFalse(writingTool.isSelected, "Done returns to Browse before reentry")
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testFreeInkSymbolGuidanceAcrossLayouts() throws {
        XCUIDevice.shared.orientation = .portrait
        let (app, arguments) = try disposableFixtureApplication()
        app.launchArguments = arguments
        app.launch()

        for title in ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"] {
            let chart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 20))
            chart.tap()
            let freeInk = app.buttons["Free Ink"]
            XCTAssertTrue(freeInk.waitForExistence(timeout: 15))
            XCTAssertFalse(freeInk.isSelected, "The normal entry starts in Browse")
            freeInk.tap()

            let purpose = app.staticTexts["editor-guidance-purpose"]
            let firstStep = app.staticTexts["editor-guidance-step-1"]
            let symbolStep = app.staticTexts["editor-guidance-step-2"]
            XCTAssertTrue(symbolStep.waitForExistence(timeout: 10))
            XCTAssertEqual(purpose.label, "Write notes and reminders on the page")
            XCTAssertTrue(firstStep.label.contains("Staff notes stay handwritten"))
            XCTAssertTrue(symbolStep.label.contains("fermata (arch over a dot)"))
            XCTAssertTrue(symbolStep.label.contains("accent (>)"))
            XCTAssertTrue(symbolStep.label.contains("Lift the Pencil and pause to render"))
            for element in [purpose, firstStep, symbolStep] {
                XCTAssertTrue(element.isHittable)
                XCTAssertGreaterThan(element.frame.height, 0)
                XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(element.frame))
            }
            let instruction = app.descendants(matching: .any)
                .matching(identifier: "editor-active-tool-instruction").firstMatch
            XCTAssertTrue(instruction.exists)
            XCTAssertEqual(purpose.frame.midX, instruction.frame.midX, accuracy: 3,
                "The purpose is centered within the helper, including the balanced Guide affordance")
            for label in ["Write", "Erase", "Done"] {
                XCTAssertTrue(app.buttons[label].isHittable)
            }
            attach(app, name: "\(title) centered Free Ink helper and symbol instructions")

            app.buttons["Free Ink guide"].tap()
            let guideBar = app.navigationBars["Free Ink guide"]
            XCTAssertTrue(guideBar.waitForExistence(timeout: 10))
            let ownership = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                "Rendering replaces only that symbol's strokes")).firstMatch
            reveal(ownership, in: app)
            XCTAssertTrue(ownership.label.contains("other handwriting stays on the page"))
            XCTAssertTrue(ownership.label.contains("keeps the original strokes with the converted mark"))
            XCTAssertTrue(ownership.isHittable)
            // These fixtures contain no converted marks. Recovery is offered
            // only when a mark exists; model tests cover its Restore Ink copy.
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Restore Ink")).count, 0)
            attach(app, name: "\(title) Free Ink guide preserves symbol source ownership")
            guideBar.buttons["Done"].tap()
            XCTAssertTrue(symbolStep.waitForExistence(timeout: 10))
            XCTAssertTrue(freeInk.isSelected)
            app.buttons["Done"].tap()
            app.buttons["Exit Chart"].tap()
            XCTAssertTrue(chart.waitForExistence(timeout: 10))
        }
        app.terminate()
    }

    @MainActor
    func testMeasureLayoutExplanationsAndDoneAcrossLayouts() throws {
        XCUIDevice.shared.orientation = .portrait
        let (app, arguments) = try disposableFixtureApplication()
        app.launchArguments = arguments
        app.launch()
        let actionIDs = ["startNewRow", "joinRowAbove", "moveToRowBelow", "evenRowWidths", "mergeWithNext"]

        for title in ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"] {
            let chart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 20))
            chart.tap()
            let measures = app.buttons["Measures"]
            XCTAssertTrue(measures.waitForExistence(timeout: 15))
            measures.tap()
            let layout = app.buttons["measure-layout-open"]
            XCTAssertTrue(layout.waitForExistence(timeout: 10))
            XCTAssertTrue(layout.isHittable)
            layout.tap()
            let bar = app.navigationBars["Measure Layout"]
            XCTAssertTrue(bar.waitForExistence(timeout: 10))
            let context = app.staticTexts["measure-layout-context"]
            XCTAssertTrue(context.waitForExistence(timeout: 5))
            let selectedMeasure = context.label
            XCTAssertNotNil(selectedMeasure.range(of: #"^Measure [1-9][0-9]* selected$"#, options: .regularExpression))
            XCTAssertTrue(app.staticTexts["measure-layout-instruction"].isHittable)
            XCTAssertTrue(bar.buttons["Done"].isHittable)

            var availability: [String: Bool] = [:]
            var explanations: [String: String] = [:]
            var reasons: [String: String] = [:]
            for actionID in actionIDs {
                let action = app.buttons["measure-layout-action-\(actionID)"]
                let explanation = app.staticTexts["measure-layout-explanation-\(actionID)"]
                reveal(explanation, in: app)
                XCTAssertTrue(action.exists)
                XCTAssertGreaterThanOrEqual(action.frame.height, 44)
                XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(action.frame),
                    "Every action remains visible beside its full explanation")
                if action.isEnabled { XCTAssertTrue(action.isHittable) }
                XCTAssertTrue(explanation.isHittable, "Every explanation is reachable by ordinary scrolling")
                XCTAssertFalse(explanation.label.isEmpty)
                XCTAssertGreaterThanOrEqual(explanation.frame.height, 14)
                XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(explanation.frame))
                if actionID == "joinRowAbove" {
                    XCTAssertTrue(explanation.label.contains("The remaining measures stay together."))
                    XCTAssertGreaterThan(explanation.frame.height, 25,
                        "The full two-sentence explanation wraps instead of using a truncated menu subtitle")
                }
                availability[actionID] = action.isEnabled
                explanations[actionID] = explanation.label
                let reason = app.descendants(matching: .any)
                    .matching(identifier: "measure-layout-reason-\(actionID)").firstMatch
                if !action.isEnabled {
                    reveal(reason, in: app)
                    XCTAssertFalse(reason.label.isEmpty, "An unavailable action explains how to make it available")
                    XCTAssertGreaterThan(reason.frame.height, 0)
                    XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(reason.frame))
                    reasons[actionID] = reason.label
                } else {
                    XCTAssertFalse(reason.exists)
                }
                attach(app, name: "\(title) \(actionID) full explanation and availability")
            }
            XCTAssertFalse(reasons.isEmpty, "A blank chart also exercises the disabled-action explanations")

            // Inspecting the sheet and Done never invokes a layout action.
            // Reopen to check unchanged selection, availability and guidance;
            // independent container readback verifies saved chart payloads.
            bar.buttons["Done"].tap()
            XCTAssertTrue(layout.waitForExistence(timeout: 10))
            XCTAssertTrue(measures.isSelected)
            layout.tap()
            XCTAssertTrue(bar.waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["measure-layout-context"].label, selectedMeasure)
            for actionID in actionIDs {
                XCTAssertEqual(app.buttons["measure-layout-action-\(actionID)"].isEnabled, availability[actionID])
                XCTAssertEqual(app.staticTexts["measure-layout-explanation-\(actionID)"].label, explanations[actionID])
                if let originalReason = reasons[actionID] {
                    let reason = app.descendants(matching: .any)
                        .matching(identifier: "measure-layout-reason-\(actionID)").firstMatch
                    XCTAssertEqual(reason.label, originalReason)
                }
            }
            bar.buttons["Done"].tap()
            XCTAssertTrue(layout.waitForExistence(timeout: 10))
            app.buttons["Exit Chart"].tap()
            XCTAssertTrue(chart.waitForExistence(timeout: 10))
        }
        app.terminate()
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
    private func disposableFixtureApplication() throws -> (XCUIApplication, [String]) {
        let languageArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        #if targetEnvironment(simulator)
        return (XCUIApplication(), ["-iChartEditorUIPreview"] + languageArguments)
        #else
        let bundleID = ProcessInfo.processInfo.environment["ICHART_ENTRY_TEST_BUNDLE_ID"] ?? ""
        try XCTSkipUnless(bundleID.hasPrefix("com.ichart.claritycrash"),
            "Physical acceptance requires an explicitly selected disposable app with synthetic fixtures.")
        return (XCUIApplication(bundleIdentifier: bundleID), languageArguments)
        #endif
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
