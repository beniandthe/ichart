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
        XCTAssertTrue(libraryText.contains("Resend Email"))
        XCTAssertTrue(libraryText.contains("Open the verification link"))
    }

    func testHomeShellPrimaryControlsKeepExplicitHitAreas() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let libraryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Library/LibraryView.swift")
        )

        XCTAssertTrue(libraryText.contains(".frame(minWidth: 180, minHeight: 44)"))
        XCTAssertTrue(libraryText.contains(".contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))"))
        XCTAssertTrue(libraryText.contains("IChartHomeSidebarButton"))
        XCTAssertTrue(libraryText.contains("IChartNewChartControl"))
    }

    func testEditorExitUsesExplicitNavigationRoute() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRootText = try String(contentsOf: projectRoot.appendingPathComponent("SmartChart/App/AppRootView.swift"))
        let editorText = try String(contentsOf: projectRoot.appendingPathComponent("SmartChart/Features/Editor/EditorView.swift"))

        XCTAssertTrue(appRootText.contains("EditorView(chart: chart, initialCanvasMode: initialCanvasMode)"))
        XCTAssertTrue(appRootText.contains("projectPath.removeAll()"))
        XCTAssertTrue(editorText.contains("private let onExit"))
        XCTAssertTrue(editorText.contains("exitEditor()"))
        XCTAssertTrue(editorText.contains("editorNavigationChrome"))
        XCTAssertTrue(editorText.contains("editorToolChrome"))
        XCTAssertTrue(editorText.contains(".toolbar(.hidden, for: .navigationBar)"))
        XCTAssertTrue(editorText.contains(".frame(width: 44, height: 44)"))
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
        let syncStoreText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Sync/ChartCloudSyncStore.swift")
        )
        let libraryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Library/LibraryView.swift")
        )
        let clientFactoryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Supabase/IChartSupabaseClientFactory.swift")
        )
        let sessionStoreText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Supabase/IChartSupabaseSessionStore.swift")
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
        XCTAssertTrue(appText.contains("IChartSupabaseClientFactory.liveClients()"))
        XCTAssertTrue(appText.contains("IChartAuthStore.live(clients:"))
        XCTAssertTrue(appText.contains("ChartCloudSyncStore.live(clients:"))
        XCTAssertTrue(configurationText.contains("SUPABASE_URL"))
        XCTAssertTrue(configurationText.contains("SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertTrue(configurationText.contains("SUPABASE_ANON_KEY"))
        XCTAssertTrue(clientFactoryText.contains("SupabaseClient("))
        XCTAssertTrue(clientFactoryText.contains("IChartSupabaseAuthLocalStorage"))
        XCTAssertTrue(clientFactoryText.contains("IChartSupabaseSessionStore"))
        XCTAssertTrue(clientFactoryText.contains("accessToken:"))
        XCTAssertTrue(clientFactoryText.contains("ichart://auth-callback"))
        XCTAssertTrue(clientFactoryText.contains("isAuthCallbackURL"))
        XCTAssertTrue(sessionStoreText.contains("IChartSupabaseSessionProviding"))
        XCTAssertTrue(sessionStoreText.contains("Auth session missing."))
        XCTAssertTrue(authStorageText.contains("KeychainLocalStorage"))
        XCTAssertTrue(authStorageText.contains("UserDefaults"))
        XCTAssertTrue(authStorageText.contains("allowsInsecureFallback"))
        XCTAssertTrue(authStorageText.contains("#if DEBUG"))
        XCTAssertTrue(authStorageText.contains("targetEnvironment(simulator)"))
        XCTAssertTrue(authStorageText.contains("IChartSupabasePersistentSessionStore"))
        XCTAssertTrue(authStorageText.contains("iChart.supabase.session.v1"))
        XCTAssertTrue(authStoreText.contains("signUp(email:"))
        XCTAssertTrue(authStoreText.contains("let session = try await authClient.auth.signIn("))
        XCTAssertTrue(authStoreText.contains("resendVerificationEmail"))
        XCTAssertTrue(authStoreText.contains("resetPasswordForEmail"))
        XCTAssertTrue(authStoreText.contains("Set new password"))
        XCTAssertTrue(authStoreText.contains("passwordRecovery"))
        XCTAssertTrue(authStoreText.contains("updatePassword(_ password:"))
        XCTAssertTrue(authStoreText.contains("UserAttributes(password: password)"))
        XCTAssertTrue(authStoreText.contains("callbackType(from:"))
        XCTAssertTrue(authStoreText.contains("verifyOTP("))
        XCTAssertTrue(authStoreText.contains("tokenHash:"))
        XCTAssertTrue(authStoreText.contains("token_hash"))
        XCTAssertTrue(authStoreText.contains("tokenHashValue(from:"))
        XCTAssertTrue(authStoreText.contains("\"token\""))
        XCTAssertTrue(authStoreText.contains("iChartPendingVerificationEmail"))
        XCTAssertTrue(authStoreText.contains("applyAuthState"))
        XCTAssertTrue(authStoreText.contains("dataClient"))
        XCTAssertTrue(authStoreText.contains("sessionStore.update"))
        XCTAssertTrue(authStoreText.contains("persistentSessionStore.store"))
        XCTAssertTrue(authStoreText.contains("restoreStoredSession"))
        XCTAssertTrue(authStoreText.contains("temporarilyOffline"))
        XCTAssertTrue(authStoreText.contains("Temporarily offline"))
        XCTAssertTrue(authStoreText.contains("Account is offline. Local charts remain available."))
        XCTAssertTrue(authStoreText.contains("isConnectivityError"))
        XCTAssertTrue(authStoreText.contains("setSession("))
        XCTAssertTrue(authStoreText.contains("redirectTo: IChartSupabaseClientFactory.authCallbackURL"))
        XCTAssertTrue(authStoreText.contains("emailRedirectTo: IChartSupabaseClientFactory.authCallbackURL"))
        XCTAssertTrue(authStoreText.contains("IChartUserProfileUpdate"))
        XCTAssertTrue(authStoreText.contains("IChartAuthError.invalidAuthCallback"))
        XCTAssertTrue(authStoreText.contains("session(from:"))
        XCTAssertFalse(authStoreText.contains("client.auth.currentUser"))
        XCTAssertTrue(syncServiceText.contains("existingSnapshotID(chartID:"))
        XCTAssertTrue(syncServiceText.contains("ignoreDuplicates: true"))
        XCTAssertTrue(syncServiceText.contains(".eq(\"version\", value: String(version))"))
        XCTAssertTrue(syncServiceText.contains("sessionProvider.currentUserID()"))
        XCTAssertTrue(syncServiceText.contains("localSnapshotForSync"))
        XCTAssertTrue(syncServiceText.contains("shouldRestoreRemoteForLegacyOwnerlessSnapshot"))
        XCTAssertFalse(syncServiceText.contains("client.auth.currentUser"))
        XCTAssertTrue(syncServiceText.contains("Cloud backup unavailable"))
        XCTAssertTrue(syncServiceText.contains("Sign in to back up"))
        XCTAssertTrue(syncServiceText.contains("Local edits are saved. Reconnect to back up."))
        XCTAssertTrue(syncServiceText.contains("manualSyncTitle"))
        XCTAssertTrue(syncServiceText.contains("Retry Sync"))
        XCTAssertTrue(syncServiceText.contains("Sync Now"))
        XCTAssertTrue(syncServiceText.contains("manualSyncDisabledReason"))
        XCTAssertTrue(syncStoreText.contains("lastSyncAttemptAt"))
        XCTAssertTrue(syncStoreText.contains("cancelPendingSyncWork()"))
        XCTAssertTrue(syncStoreText.contains("case .temporarilyOffline"))
        XCTAssertTrue(syncStoreText.contains(".notConnectedToInternet"))
        XCTAssertTrue(syncStoreText.contains("Sign in again to resume cloud backup."))
        XCTAssertTrue(syncStoreText.contains("Cloud permissions blocked backup. Sign in again, then retry."))
        XCTAssertTrue(syncStoreText.contains("We could not finish cloud backup. Retry when you are ready."))
        XCTAssertTrue(libraryText.contains("IChartCloudSyncSettings"))
        XCTAssertTrue(libraryText.contains("Reconnect"))
        XCTAssertTrue(libraryText.contains("Save Password"))
        XCTAssertTrue(libraryText.contains("Last Checked"))
        XCTAssertTrue(libraryText.contains("syncStore.state.manualSyncTitle"))
        XCTAssertTrue(libraryText.contains("syncStore.state.manualSyncDisabledReason"))
        XCTAssertTrue(libraryText.contains("statusTint"))
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
        let configText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/config.toml")
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
        XCTAssertTrue(configText.contains("max_frequency = \"1m\""))
        XCTAssertTrue(configText.contains("otp_length = 6"))
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
        let productionReadinessText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/supabase-production-readiness-checklist.md")
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
        let productionReadinessScriptText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("scripts/run_supabase_production_readiness.sh")
        )

        XCTAssertTrue(gitignoreText.contains("!.env.example"))
        XCTAssertTrue(envExampleText.contains("SUPABASE_URL"))
        XCTAssertTrue(envExampleText.contains("SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertFalse(envExampleText.contains("eyJ"))
        XCTAssertTrue(runbookText.contains("supabase db reset"))
        XCTAssertTrue(runbookText.contains("supabase db push"))
        XCTAssertTrue(runbookText.contains("ichart://auth-callback"))
        XCTAssertTrue(runbookText.contains("blank browser page"))
        XCTAssertTrue(runbookText.contains("custom SMTP"))
        XCTAssertTrue(runbookText.contains("supabase status -o env"))
        XCTAssertTrue(runbookText.contains("remote project settings cannot accidentally redirect local RLS/integration tests"))
        XCTAssertTrue(runbookText.contains("scripts/run_supabase_production_readiness.sh"))
        XCTAssertTrue(runbookText.contains("docs/supabase-production-readiness-checklist.md"))
        XCTAssertTrue(productionReadinessText.contains("Auth email/password provider is enabled"))
        XCTAssertTrue(productionReadinessText.contains("ichart://auth-callback"))
        XCTAssertTrue(productionReadinessText.contains("Email templates keep a confirmation link flow"))
        XCTAssertTrue(productionReadinessText.contains("service-role keys"))
        XCTAssertTrue(productionReadinessText.contains("Sync Now"))
        XCTAssertTrue(productionReadinessText.contains("Retry Sync"))
        XCTAssertTrue(productionReadinessText.contains("Restore/Reinstall Gate"))
        XCTAssertTrue(productionReadinessText.contains("Data And RLS Gate"))
        XCTAssertTrue(supabaseConfigText.contains("project_id = \"smart-chart\""))
        XCTAssertTrue(supabaseConfigText.contains("additional_redirect_urls = [\"ichart://auth-callback\"]"))
        XCTAssertTrue(supabaseConfigText.contains("enable_confirmations = true"))
        XCTAssertTrue(supabaseConfigText.contains("secure_password_change = true"))
        XCTAssertTrue(supabaseConfigText.contains("max_frequency = \"1m\""))
        XCTAssertTrue(supabaseConfigText.contains("otp_length = 6"))
        XCTAssertTrue(rlsTestText.contains("owner can insert own chart document"))
        XCTAssertTrue(rlsTestText.contains("client cannot update subscription rows"))
        XCTAssertTrue(rlsTestText.contains("client cannot update stripe customer id on profile"))
        XCTAssertTrue(rlsTestText.contains("latest snapshot pointer cannot reference a missing snapshot"))
        XCTAssertTrue(integrationTestText.contains("SMART_CHART_SUPABASE_INTEGRATION"))
        XCTAssertTrue(integrationTestText.contains("SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertTrue(integrationTestText.contains("confirmLocalSignupEmail"))
        XCTAssertTrue(integrationTestText.contains("over_email_send_rate_limit"))
        XCTAssertTrue(integrationTestText.contains("latest_snapshot_id"))
        XCTAssertFalse(integrationTestText.contains("SERVICE_ROLE"))
        XCTAssertTrue(qaScriptText.contains("SUPABASE_CMD"))
        XCTAssertTrue(qaScriptText.contains("npx --yes supabase"))
        XCTAssertTrue(qaScriptText.contains("supabase_cli db reset"))
        XCTAssertTrue(qaScriptText.contains("supabase_cli status -o env"))
        XCTAssertTrue(qaScriptText.contains("API_URL"))
        XCTAssertTrue(qaScriptText.contains("PUBLISHABLE_KEY"))
        XCTAssertTrue(qaScriptText.contains("supabase_cli test db"))
        XCTAssertTrue(qaScriptText.contains("--filter SupabaseIntegrationTests"))
        XCTAssertTrue(productionReadinessScriptText.contains("git diff --check"))
        XCTAssertTrue(productionReadinessScriptText.contains("scan_for_secrets"))
        XCTAssertTrue(productionReadinessScriptText.contains("SMART_CHART_RUN_LOCAL_SUPABASE_QA"))
        XCTAssertTrue(productionReadinessScriptText.contains("scripts/run_supabase_local_qa.sh"))
        XCTAssertTrue(productionReadinessScriptText.contains("ProjectConfigurationTests|ChartCloudMergeTests|ChartLibraryStoreTests|SupabaseIntegrationTests"))
        XCTAssertTrue(productionReadinessScriptText.contains("SUPABASE_SERVICE_ROLE_KEY"))
        XCTAssertTrue(productionReadinessScriptText.contains("Manual simulator/cloud gate still required"))
    }
}
