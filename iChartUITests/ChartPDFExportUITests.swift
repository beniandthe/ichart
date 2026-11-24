import XCTest

/// Exercises the normal export and system Share routes with disposable charts.
/// Generated library PDFs remain available for independent container readback.
final class ChartPDFExportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEditorExportsAndOpensSystemShareInBothChartStyles() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("PDF export acceptance uses disposable Simulator editor fixtures only.")
        #else
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-iChartEditorUIPreview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-iChartChartPreviewMode", "collapsed", "-iChartChartsWorkspaceMode", "charts",
            "-iChartHasSeenAccountLanding", "NO", "-iChartHasSeenGuidedTourOffer", "YES"
        ]
        for title in ["Simple Sheet UI Fixture", "Rhythm Section UI Fixture"] {
            app.launch()
            defer { app.terminate() }
            let chart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 20))
            chart.tap()
            let export = app.buttons["Export PDF"]
            XCTAssertTrue(export.waitForExistence(timeout: 15))
            XCTAssertTrue(export.isEnabled)
            XCTAssertTrue(export.isHittable)
            export.tap()

            let done = app.buttons["pdf.preview.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 20), "A normal export must open its saved PDF preview")
            XCTAssertTrue(done.isHittable)
            let preview = app.navigationBars[title]
            XCTAssertTrue(preview.exists)
            let metadata = app.descendants(matching: .any).matching(identifier: "pdf.preview.metadata").firstMatch
            XCTAssertTrue(metadata.exists)
            attach(app, name: "\(title) saved PDF preview")

            let share = preview.buttons["Share"]
            XCTAssertTrue(share.waitForExistence(timeout: 5))
            XCTAssertTrue(share.isHittable)
            share.tap()
            let activityList = app.descendants(matching: .any).matching(identifier: "ActivityListView").firstMatch
            let systemActivities = app.descendants(matching: .any).matching(
                NSPredicate(format: "label IN %@", ["Copy", "Print", "Save to Files"]))
            let presented = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                activityList.exists || systemActivities.firstMatch.exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [presented], timeout: 10), .completed,
                "Share must open the system activity sheet for the generated PDF")
            attach(app, name: "\(title) system Share")
            // No share destination is selected. Terminating this disposable
            // process closes the activity sheet before the next fixture launch.
        }
        #endif
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
