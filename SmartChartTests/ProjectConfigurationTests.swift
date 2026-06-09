import XCTest

final class ProjectConfigurationTests: XCTestCase {
    func testIPadBuildDeclaresFullScreenAndAllOrientations() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFile = projectRoot.appendingPathComponent("project.yml")
        let projectText = try String(contentsOf: projectFile)

        XCTAssertTrue(projectText.contains("INFOPLIST_KEY_UIRequiresFullScreen: true"))
        XCTAssertTrue(projectText.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad:"))
        XCTAssertTrue(projectText.contains("UIInterfaceOrientationPortrait"))
        XCTAssertTrue(projectText.contains("UIInterfaceOrientationPortraitUpsideDown"))
        XCTAssertTrue(projectText.contains("UIInterfaceOrientationLandscapeLeft"))
        XCTAssertTrue(projectText.contains("UIInterfaceOrientationLandscapeRight"))
    }

    func testLaunchHandwritingIsBundledAndNotUserConfigurable() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRootText = try String(contentsOf: projectRoot.appendingPathComponent("SmartChart/App/AppRootView.swift"))
        let libraryText = try String(contentsOf: projectRoot.appendingPathComponent("SmartChart/Features/Library/LibraryView.swift"))
        let bundledLaunchSampleURL = projectRoot
            .appendingPathComponent("SmartChart/Resources/Launch/IChartCanonicalLaunchHandwriting.json")
        let bundledLaunchSampleText = try String(contentsOf: bundledLaunchSampleURL)

        XCTAssertTrue(appRootText.contains("IChartLaunchScreenView"))
        XCTAssertTrue(appRootText.contains("bundledCanonicalLaunchSample"))
        XCTAssertTrue(appRootText.contains("IChartCanonicalLaunchHandwriting"))
        XCTAssertTrue(appRootText.contains("subdirectory: canonicalResourceSubdirectory"))
        XCTAssertTrue(appRootText.contains("bundle.url("))
        XCTAssertFalse(appRootText.contains("@AppStorage"))
        XCTAssertFalse(appRootText.contains("iChartLaunchHandwriting"))
        XCTAssertFalse(libraryText.contains("Launch Handwriting"))
        XCTAssertTrue(bundledLaunchSampleText.contains("\"strokes\""))
    }

    func testChordConfirmationOffersKeyboardManualEntry() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sheetText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Editor/Components/ChordInkSheetViews.swift")
        )

        XCTAssertTrue(sheetText.contains("No confident suggestions"))
        XCTAssertTrue(sheetText.contains("Open keyboard for manual chord entry"))
        XCTAssertTrue(sheetText.contains("systemImage: \"keyboard\""))
    }

    func testSettingsContainUserInfoAndPaymentInfo() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let libraryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Library/LibraryView.swift")
        )

        XCTAssertTrue(libraryText.contains("iChartUserEmail"))
        XCTAssertTrue(libraryText.contains("iChartUserPhone"))
        XCTAssertTrue(libraryText.contains("iChartUserAddress"))
        XCTAssertTrue(libraryText.contains("iChartUserPaymentSummary"))
        XCTAssertTrue(libraryText.contains("User Info"))
        XCTAssertTrue(libraryText.contains("Payment Info"))
    }
}
