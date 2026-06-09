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

    func testSupabasePackageAndConfigurationAreWired() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectText = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let appText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/SmartChartApp.swift")
        )
        let configurationText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Supabase/IChartSupabaseConfiguration.swift")
        )
        let authStoreText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Auth/IChartAuthStore.swift")
        )

        XCTAssertTrue(projectText.contains("https://github.com/supabase/supabase-swift.git"))
        XCTAssertTrue(projectText.contains("product: Supabase"))
        XCTAssertTrue(projectText.contains("INFOPLIST_KEY_SupabaseURL"))
        XCTAssertTrue(projectText.contains("INFOPLIST_KEY_SupabasePublishableKey"))
        XCTAssertTrue(projectText.contains("INFOPLIST_KEY_SupabaseAnonKey"))
        XCTAssertTrue(appText.contains("IChartAuthStore.live()"))
        XCTAssertTrue(configurationText.contains("SUPABASE_URL"))
        XCTAssertTrue(configurationText.contains("SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertTrue(configurationText.contains("SUPABASE_ANON_KEY"))
        XCTAssertTrue(authStoreText.contains("SupabaseClient("))
        XCTAssertTrue(authStoreText.contains("signUp(email:"))
        XCTAssertTrue(authStoreText.contains("resendVerificationEmail"))
        XCTAssertFalse(configurationText.contains("eyJ"))
    }

    func testSupabaseMigrationCreatesProtectedAccountAndChartTables() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migrationText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/migrations/20260609133000_initial_auth_profiles_and_charts.sql")
        )

        XCTAssertTrue(migrationText.contains("create table public.profiles"))
        XCTAssertTrue(migrationText.contains("create table public.chart_documents"))
        XCTAssertTrue(migrationText.contains("create table public.chart_snapshots"))
        XCTAssertTrue(migrationText.contains("create table public.subscriptions"))
        XCTAssertTrue(migrationText.contains("create table public.devices"))
        XCTAssertTrue(migrationText.contains("enable row level security"))
        XCTAssertTrue(migrationText.contains("auth.uid() = owner_id"))
        XCTAssertTrue(migrationText.contains("auth.uid() = id"))
        XCTAssertTrue(migrationText.contains("handle_new_auth_user"))
        XCTAssertTrue(migrationText.contains("stripe_customer_id"))
        XCTAssertFalse(migrationText.contains("card_number"))
    }
}
