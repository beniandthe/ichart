import XCTest

final class ProjectConfigurationTests: XCTestCase {
    func testIPadBuildDeclaresFullScreenAndAllOrientations() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFile = projectRoot.appendingPathComponent("project.yml")
        let projectText = try String(contentsOf: projectFile)

        XCTAssertTrue(projectText.contains("UIRequiresFullScreen: true"))
        XCTAssertTrue(projectText.contains("UISupportedInterfaceOrientations~ipad:"))
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
        let syncServiceText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Sync/ChartCloudSyncService.swift")
        )
        let clientFactoryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Supabase/IChartSupabaseClientFactory.swift")
        )
        let authStorageText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Supabase/IChartSupabaseAuthLocalStorage.swift")
        )

        XCTAssertTrue(projectText.contains("https://github.com/supabase/supabase-swift.git"))
        XCTAssertTrue(projectText.contains("product: Supabase"))
        XCTAssertTrue(projectText.contains("path: SmartChart/App/Info.plist"))
        XCTAssertTrue(projectText.contains("SupabaseURL: \"$(SUPABASE_URL)\""))
        XCTAssertTrue(projectText.contains("SupabasePublishableKey: \"$(SUPABASE_PUBLISHABLE_KEY)\""))
        XCTAssertTrue(projectText.contains("SupabaseAnonKey: \"$(SUPABASE_ANON_KEY)\""))
        XCTAssertTrue(projectText.contains("CFBundleURLTypes:"))
        XCTAssertTrue(projectText.contains("ichart"))
        XCTAssertTrue(appText.contains("IChartAuthStore.live(client:"))
        XCTAssertTrue(appText.contains("ChartCloudSyncStore.live(client:"))
        XCTAssertTrue(configurationText.contains("SUPABASE_URL"))
        XCTAssertTrue(configurationText.contains("SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertTrue(configurationText.contains("SUPABASE_ANON_KEY"))
        XCTAssertTrue(clientFactoryText.contains("SupabaseClient("))
        XCTAssertTrue(clientFactoryText.contains("IChartSupabaseAuthLocalStorage"))
        XCTAssertTrue(clientFactoryText.contains("ichart://auth-callback"))
        XCTAssertTrue(clientFactoryText.contains("isAuthCallbackURL"))
        XCTAssertTrue(authStorageText.contains("KeychainLocalStorage"))
        XCTAssertTrue(authStorageText.contains("UserDefaults"))
        XCTAssertTrue(authStorageText.contains("allowsInsecureFallback"))
        XCTAssertTrue(authStorageText.contains("#if DEBUG"))
        XCTAssertTrue(authStoreText.contains("signUp(email:"))
        XCTAssertTrue(authStoreText.contains("let session = try await client.auth.signIn("))
        XCTAssertTrue(authStoreText.contains("resendVerificationEmail"))
        XCTAssertTrue(authStoreText.contains("resetPasswordForEmail"))
        XCTAssertTrue(authStoreText.contains("redirectTo: IChartSupabaseClientFactory.authCallbackURL"))
        XCTAssertTrue(authStoreText.contains("IChartUserProfileUpdate"))
        XCTAssertTrue(authStoreText.contains("IChartAuthError.invalidAuthCallback"))
        XCTAssertTrue(authStoreText.contains("session(from:"))
        XCTAssertTrue(syncServiceText.contains("existingSnapshotID(chartID:"))
        XCTAssertTrue(syncServiceText.contains("ignoreDuplicates: true"))
        XCTAssertTrue(syncServiceText.contains(".eq(\"version\", value: String(version))"))
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
        XCTAssertTrue(migrationText.contains("deleted_at timestamptz"))
        XCTAssertTrue(migrationText.contains("remote_revision bigint"))
        XCTAssertTrue(migrationText.contains("client_updated_at timestamptz"))
        XCTAssertTrue(migrationText.contains("enable row level security"))
        XCTAssertTrue(migrationText.contains("auth.uid() = owner_id"))
        XCTAssertTrue(migrationText.contains("auth.uid() = id"))
        XCTAssertTrue(migrationText.contains("chart_snapshots.chart_id = chart_documents.id"))
        XCTAssertTrue(migrationText.contains("handle_new_auth_user"))
        XCTAssertTrue(migrationText.contains("stripe_customer_id"))
        XCTAssertTrue(migrationText.contains("revoke all on table public.subscriptions from anon, authenticated"))
        XCTAssertTrue(migrationText.contains("grant select on table public.subscriptions to authenticated"))
        XCTAssertTrue(migrationText.contains("grant insert (id, email, phone, mailing_address, payment_summary)"))
        XCTAssertFalse(migrationText.contains("chart_snapshots_update_own"))
        XCTAssertFalse(migrationText.contains("card_number"))
    }

    func testSupabaseRunbookAndRlsSmokeTestsArePresent() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let gitignoreText = try String(contentsOf: projectRoot.appendingPathComponent(".gitignore"))
        let envExampleText = try String(contentsOf: projectRoot.appendingPathComponent(".env.example"))
        let runbookText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/supabase-integration-runbook.md")
        )
        let rlsTestText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/tests/rls_smoke.sql")
        )
        let supabaseConfigText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/config.toml")
        )
        let integrationTestText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChartTests/SupabaseIntegrationTests.swift")
        )
        let qaScriptText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("scripts/run_supabase_local_qa.sh")
        )

        XCTAssertTrue(gitignoreText.contains("!.env.example"))
        XCTAssertTrue(envExampleText.contains("SUPABASE_URL"))
        XCTAssertTrue(envExampleText.contains("SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertFalse(envExampleText.contains("eyJ"))
        XCTAssertTrue(runbookText.contains("supabase db reset"))
        XCTAssertTrue(runbookText.contains("supabase db push"))
        XCTAssertTrue(runbookText.contains("ichart://auth-callback"))
        XCTAssertTrue(supabaseConfigText.contains("project_id = \"smart-chart\""))
        XCTAssertTrue(supabaseConfigText.contains("additional_redirect_urls = [\"ichart://auth-callback\"]"))
        XCTAssertTrue(supabaseConfigText.contains("enable_confirmations = true"))
        XCTAssertTrue(supabaseConfigText.contains("secure_password_change = true"))
        XCTAssertTrue(rlsTestText.contains("owner can insert own chart document"))
        XCTAssertTrue(rlsTestText.contains("client cannot update subscription rows"))
        XCTAssertTrue(rlsTestText.contains("client cannot update stripe customer id on profile"))
        XCTAssertTrue(rlsTestText.contains("latest snapshot pointer cannot reference a missing snapshot"))
        XCTAssertTrue(integrationTestText.contains("SMART_CHART_SUPABASE_INTEGRATION"))
        XCTAssertTrue(integrationTestText.contains("SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertTrue(integrationTestText.contains("confirmLocalSignupEmail"))
        XCTAssertTrue(integrationTestText.contains("latest_snapshot_id"))
        XCTAssertFalse(integrationTestText.contains("SERVICE_ROLE"))
        XCTAssertTrue(qaScriptText.contains("supabase db reset"))
        XCTAssertTrue(qaScriptText.contains("supabase test db"))
        XCTAssertTrue(qaScriptText.contains("--filter SupabaseIntegrationTests"))
    }
}
