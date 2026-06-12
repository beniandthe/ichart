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

    func testSettingsContainUserInfoWithoutPaymentInfo() throws {
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
        XCTAssertTrue(libraryText.contains("User Info"))
        XCTAssertFalse(libraryText.contains("iChartUserPaymentSummary"))
        XCTAssertFalse(libraryText.contains("Payment Info"))
        XCTAssertTrue(libraryText.contains("Resend Email"))
        XCTAssertTrue(libraryText.contains("Open the verification link"))
    }

    func testManualTextEntryPopoutsExposeKeyboardButtons() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let libraryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Library/LibraryView.swift")
        )
        let headerSheetText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Editor/Components/ChartHeaderSheetView.swift")
        )
        let editorText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Editor/EditorView.swift")
        )
        let chordSheetText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Editor/Components/ChordInkSheetViews.swift")
        )

        XCTAssertTrue(libraryText.contains("IChartKeyboardFocusButton"))
        XCTAssertTrue(libraryText.contains("field: .firstName"))
        XCTAssertTrue(libraryText.contains("accessibilityLabel: \"Open keyboard for \\(title)\""))
        XCTAssertTrue(libraryText.contains("Open keyboard for chart title"))
        XCTAssertTrue(libraryText.contains("Open keyboard for project title"))
        XCTAssertTrue(libraryText.contains("Open keyboard for variant title"))
        XCTAssertTrue(headerSheetText.contains("focusedField = .title"))
        XCTAssertTrue(headerSheetText.contains("Open keyboard for \\(title)"))
        XCTAssertTrue(editorText.contains("Open keyboard for text entry"))
        XCTAssertTrue(chordSheetText.contains("Open keyboard for chord correction"))
    }

    func testFirstRunAccountLandingIsMandatoryAndCollectsName() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let libraryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Library/LibraryView.swift")
        )
        let appRootText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/AppRootView.swift")
        )
        let authStoreText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/Auth/IChartAuthStore.swift")
        )
        let profileNamesMigrationText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/migrations/20260612182458_add_profile_names.sql")
        )
        let planPolicyText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/ichart-plan-policy-source-of-truth.md")
        )

        XCTAssertTrue(libraryText.contains("IChartFirstRunAccountLandingView"))
        XCTAssertTrue(libraryText.contains("requiresNameForSignup: true"))
        XCTAssertTrue(libraryText.contains("First Name"))
        XCTAssertTrue(libraryText.contains("Last Name"))
        XCTAssertTrue(libraryText.contains(".fullScreenCover(isPresented: $showingAccountLanding)"))
        XCTAssertTrue(libraryText.contains(".frame(maxWidth: 640)"))
        XCTAssertTrue(libraryText.contains(".frame(minHeight: proxy.size.height, alignment: .center)"))
        XCTAssertTrue(libraryText.contains(".interactiveDismissDisabled(true)"))
        XCTAssertTrue(libraryText.contains("showsSignedInActions: false"))
        XCTAssertTrue(libraryText.contains("authStore.state.isVerifiedSignedIn"))
        XCTAssertTrue(libraryText.contains("Label(\"Continue\", systemImage: \"arrow.right\")"))
        XCTAssertTrue(libraryText.contains("IChartLaunchScreenView("))
        XCTAssertTrue(libraryText.contains("IChartLaunchHandwritingSample.bundledCanonicalLaunchSample()"))
        XCTAssertTrue(libraryText.contains("completeFirstRunAccountLanding"))
        XCTAssertTrue(libraryText.contains("hasSeenAccountLanding = true"))
        XCTAssertFalse(libraryText.contains("Continue to Charts"))
        XCTAssertFalse(libraryText.contains("Button(\"Close\")"))
        XCTAssertTrue(appRootText.contains("hasSeenAccountLandingKey"))
        XCTAssertTrue(appRootText.contains("UserDefaults.standard.bool(forKey: Self.hasSeenAccountLandingKey)"))
        XCTAssertTrue(appRootText.contains("struct IChartLaunchScreenView"))
        XCTAssertTrue(authStoreText.contains("firstName = \"first_name\""))
        XCTAssertTrue(authStoreText.contains("lastName = \"last_name\""))
        XCTAssertTrue(authStoreText.contains("data: signupMetadata(firstName: firstName, lastName: lastName)"))
        XCTAssertTrue(profileNamesMigrationText.contains("add column if not exists first_name text"))
        XCTAssertTrue(profileNamesMigrationText.contains("add column if not exists last_name text"))
        XCTAssertTrue(profileNamesMigrationText.contains("new.raw_user_meta_data ->> 'first_name'"))
        XCTAssertTrue(profileNamesMigrationText.contains("new.raw_user_meta_data ->> 'last_name'"))
        XCTAssertTrue(planPolicyText.contains("First-launch account creation requires first name, last name, email, and password"))
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

    func testChartConsolidationUsesSingleDeleteList() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let libraryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Library/LibraryView.swift")
        )

        XCTAssertTrue(libraryText.contains("IChartChartConsolidationNotice"))
        XCTAssertTrue(libraryText.contains("activeChartPreviewMode"))
        XCTAssertTrue(libraryText.contains("Label(\"Delete Local\", systemImage: \"trash\")"))
        XCTAssertFalse(libraryText.contains("IChartBasicChartPruningPanel"))
        XCTAssertFalse(libraryText.contains("Label(\"Remove Local\""))
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
        let syncStateText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Models/ChartSyncState.swift")
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
        XCTAssertTrue(authStoreText.contains("func signUp("))
        XCTAssertTrue(authStoreText.contains("signupMetadata(firstName:"))
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
        XCTAssertFalse(syncServiceText.contains("enum ChartSyncState"))
        XCTAssertTrue(syncStateText.contains("enum ChartSyncState"))
        XCTAssertTrue(syncStateText.contains("Cloud backup unavailable"))
        XCTAssertTrue(syncStateText.contains("Sign in to back up"))
        XCTAssertTrue(syncStateText.contains("Cloud backup requires Pro"))
        XCTAssertTrue(syncStateText.contains("Local edits are saved. Reconnect to back up."))
        XCTAssertTrue(syncStateText.contains("manualSyncTitle"))
        XCTAssertTrue(syncStateText.contains("Retry Sync"))
        XCTAssertTrue(syncStateText.contains("Sync Now"))
        XCTAssertTrue(syncStateText.contains("manualSyncDisabledReason"))
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

    func testStoreKitSubscriptionAuthorityIsWired() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectText = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let appText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/SmartChartApp.swift")
        )
        let catalogText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Models/IChartStoreKitProductCatalog.swift")
        )
        let storeKitText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift")
        )
        let libraryText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Library/LibraryView.swift")
        )
        let upgradeText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("SmartChart/Features/Editor/Components/UpgradeSheetView.swift")
        )
        let planPolicyText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/ichart-plan-policy-source-of-truth.md")
        )
        let storeKitRunbookText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/ichart-storekit-subscription-runbook.md")
        )
        let storeKitConfigURL = projectRoot
            .appendingPathComponent("StoreKit/iChartProSubscriptions.storekit")
        let storeKitConfigText = try String(contentsOf: storeKitConfigURL)
        let storeKitConfigData = try Data(contentsOf: storeKitConfigURL)
        let storeKitConfigJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: storeKitConfigData) as? [String: Any]
        )

        XCTAssertTrue(projectText.contains("fileGroups:"))
        XCTAssertTrue(projectText.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG"))
        XCTAssertTrue(projectText.contains("- StoreKit"))
        XCTAssertTrue(projectText.contains("- path: StoreKit"))
        XCTAssertTrue(projectText.contains("buildPhase: resources"))
        XCTAssertTrue(projectText.contains("storeKitConfiguration: StoreKit/iChartProSubscriptions.storekit"))
        XCTAssertTrue(catalogText.contains("com.smartchart.app.pro.monthly"))
        XCTAssertTrue(catalogText.contains("com.smartchart.app.pro.annual"))
        XCTAssertTrue(catalogText.contains("iChartProSubscriptions.storekit"))
        XCTAssertTrue(catalogText.contains("IChartStoreKitEntitlementResolver"))
        XCTAssertTrue(storeKitConfigText.contains("\"productID\": \"com.smartchart.app.pro.monthly\""))
        XCTAssertTrue(storeKitConfigText.contains("\"productID\": \"com.smartchart.app.pro.annual\""))
        XCTAssertTrue(storeKitConfigText.contains("\"displayPrice\": \"7.99\""))
        XCTAssertTrue(storeKitConfigText.contains("\"displayPrice\": \"64.99\""))
        XCTAssertTrue(storeKitConfigText.contains("\"recurringSubscriptionPeriod\": \"P1M\""))
        XCTAssertTrue(storeKitConfigText.contains("\"recurringSubscriptionPeriod\": \"P1Y\""))
        XCTAssertEqual(
            (storeKitConfigJSON["version"] as? [String: Any])?["major"] as? Int,
            3
        )
        XCTAssertTrue(storeKitText.contains("Product.products(for: productIDs)"))
        XCTAssertTrue(storeKitText.contains("Transaction.currentEntitlements"))
        XCTAssertTrue(storeKitText.contains("Transaction.updates"))
        XCTAssertTrue(storeKitText.contains("#if DEBUG && targetEnvironment(simulator)"))
        XCTAssertTrue(storeKitText.contains("localStoreKitProductOptions()"))
        XCTAssertTrue(storeKitText.contains("applyLocalPreview(.activePro(verifiedAt: Date()))"))
        XCTAssertTrue(storeKitText.contains("Local Pro preview active for simulator QA."))
        XCTAssertTrue(storeKitText.contains("product.purchase()"))
        XCTAssertTrue(storeKitText.contains("AppStore.sync()"))
        XCTAssertTrue(storeKitText.contains("AppStore.showManageSubscriptions(in: scene)"))
        XCTAssertTrue(storeKitText.contains("Opening subscription management..."))
        XCTAssertTrue(storeKitText.contains("IChartStoreKitEntitlementResolver.entitlement"))
        XCTAssertTrue(appText.contains("@StateObject private var subscriptionStore"))
        XCTAssertTrue(appText.contains("IChartStoreKitSubscriptionStore.live()"))
        XCTAssertTrue(appText.contains("await subscriptionStore.bootstrap()"))
        XCTAssertTrue(appText.contains("store.applySubscriptionState(subscriptionStore.entitlement)"))
        XCTAssertTrue(appText.contains(".environmentObject(subscriptionStore)"))
        XCTAssertTrue(libraryText.contains("@EnvironmentObject private var subscriptionStore"))
        XCTAssertTrue(libraryText.contains("Pro Subscription"))
        XCTAssertTrue(libraryText.contains("Restore Purchases"))
        XCTAssertTrue(libraryText.contains("Manage Subscription"))
        XCTAssertTrue(libraryText.contains("subscriptionStore.productOptions"))
        XCTAssertTrue(libraryText.contains("product.valueBadge"))
        XCTAssertTrue(libraryText.contains("subscriptionStore.applyLocalPreview(subscriptionState)"))
        XCTAssertTrue(libraryText.contains("subscriptionStore.purchase(product)"))
        XCTAssertTrue(libraryText.contains("subscriptionStore.manageSubscriptions()"))
        XCTAssertTrue(upgradeText.contains("@EnvironmentObject private var subscriptionStore"))
        XCTAssertTrue(upgradeText.contains("subscriptionStore.productOptions"))
        XCTAssertTrue(upgradeText.contains("product.valueBadge"))
        XCTAssertTrue(upgradeText.contains("subscriptionStore.purchase(product)"))
        XCTAssertTrue(upgradeText.contains("subscriptionStore.restorePurchases()"))
        XCTAssertTrue(upgradeText.contains("Manage Subscription"))
        XCTAssertTrue(upgradeText.contains("subscriptionStore.manageSubscriptions()"))
        XCTAssertFalse(upgradeText.contains("until StoreKit is wired"))
        XCTAssertTrue(planPolicyText.contains("StoreKit owns Apple subscription purchase/restore."))
        XCTAssertTrue(planPolicyText.contains("StoreKit/iChartProSubscriptions.storekit"))
        XCTAssertTrue(planPolicyText.contains("Supabase subscription rows are read-only from the app and may mirror server-owned provider"))
        XCTAssertTrue(storeKitRunbookText.contains("com.smartchart.app.pro.monthly"))
        XCTAssertTrue(storeKitRunbookText.contains("com.smartchart.app.pro.annual"))
        XCTAssertTrue(storeKitRunbookText.contains("$7.99/month"))
        XCTAssertTrue(storeKitRunbookText.contains("$64.99/year"))
        XCTAssertTrue(storeKitRunbookText.contains("StoreKit/iChartProSubscriptions.storekit"))
        XCTAssertTrue(storeKitRunbookText.contains("App Store Connect Production Gate"))
        XCTAssertTrue(storeKitRunbookText.contains("subscription group for iChart Pro"))
        XCTAssertTrue(storeKitRunbookText.contains("up to 1 hour to appear in the sandbox environment"))
        XCTAssertTrue(storeKitRunbookText.contains("App Store Server Notifications"))
        XCTAssertTrue(storeKitRunbookText.contains("App Store Server API"))
        XCTAssertTrue(storeKitRunbookText.contains("Settings and the upgrade sheet expose Manage Subscription"))
        XCTAssertTrue(storeKitRunbookText.contains("Have the verified server path write the subscription authority metadata in `subscriptions`; the iOS app remains select-only."))
        XCTAssertTrue(storeKitRunbookText.contains("StoreKit is an entitlement source"))
        XCTAssertTrue(storeKitRunbookText.contains("Keep service-role keys, webhook secrets, App Store Connect API keys, and signing keys out of the iOS app and out of git."))
    }

    func testAppStoreServerNotificationFunctionIsLockedUntilVerificationIsWired() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let supabaseConfigText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/config.toml")
        )
        let functionText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/functions/app-store-server-notifications/index.mjs")
        )
        let claimFunctionText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/functions/storekit-subscription-claims/index.mjs")
        )
        let authorityText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/functions/_shared/app_store_subscription_authority.mjs")
        )
        let authorityTestText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/functions/_shared/app_store_subscription_authority.test.mjs")
        )
        let storeKitRunbookText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/ichart-storekit-subscription-runbook.md")
        )
        let productionReadinessText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/supabase-production-readiness-checklist.md")
        )
        let planPolicyText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("docs/ichart-plan-policy-source-of-truth.md")
        )

        XCTAssertTrue(supabaseConfigText.contains("[functions.app-store-server-notifications]"))
        XCTAssertTrue(supabaseConfigText.contains("verify_jwt = false"))
        XCTAssertTrue(supabaseConfigText.contains("entrypoint = \"./functions/app-store-server-notifications/index.mjs\""))
        XCTAssertTrue(supabaseConfigText.contains("[functions.storekit-subscription-claims]"))
        XCTAssertTrue(supabaseConfigText.contains("verify_jwt = true"))
        XCTAssertTrue(supabaseConfigText.contains("entrypoint = \"./functions/storekit-subscription-claims/index.mjs\""))
        XCTAssertFalse(supabaseConfigText.contains("app-store-server-notifications/index.ts"))
        XCTAssertFalse(supabaseConfigText.contains("@supabase/server"))
        XCTAssertTrue(functionText.contains("handleAppStoreServerNotificationRequest"))
        XCTAssertTrue(claimFunctionText.contains("handleStoreKitSubscriptionClaimRequest"))
        XCTAssertFalse(functionText.contains("Hello from Functions"))
        XCTAssertFalse(functionText.contains("withSupabase"))
        XCTAssertFalse(claimFunctionText.contains("withSupabase"))
        XCTAssertTrue(authorityText.contains("com.smartchart.app.pro.monthly"))
        XCTAssertTrue(authorityText.contains("com.smartchart.app.pro.annual"))
        XCTAssertTrue(authorityText.contains("App Store signedPayload verification is not configured."))
        XCTAssertTrue(authorityText.contains("writeSubscriptionAuthority"))
        XCTAssertTrue(authorityText.contains("Missing App Store signedPayload."))
        XCTAssertTrue(authorityText.contains("Nested App Store signed payload verification is not configured."))
        XCTAssertTrue(authorityText.contains("Verified App Store payload is missing subscription identity fields."))
        XCTAssertTrue(authorityText.contains("StoreKit signed transaction verification is not configured."))
        XCTAssertTrue(authorityText.contains("writeSubscriptionAuthorityClaim"))
        XCTAssertTrue(authorityText.contains("Verified StoreKit transaction is not an iChart Pro subscription."))
        XCTAssertTrue(authorityText.contains("Authenticated user resolver is not configured."))
        XCTAssertTrue(authorityTestText.contains("webhook refuses to process signedPayload without verifier"))
        XCTAssertTrue(authorityTestText.contains("webhook refuses nested signed payloads until nested verifiers are configured"))
        XCTAssertTrue(authorityTestText.contains("webhook refuses verified payloads without subscription identity fields"))
        XCTAssertTrue(authorityTestText.contains("transaction claim refuses to process without verifier"))
        XCTAssertTrue(authorityTestText.contains("transaction claim writes only after user and transaction are verified"))
        XCTAssertTrue(authorityTestText.contains("unknown products never unlock pro"))
        XCTAssertTrue(storeKitRunbookText.contains("supabase/functions/app-store-server-notifications/index.mjs"))
        XCTAssertTrue(storeKitRunbookText.contains("supabase/functions/storekit-subscription-claims/index.mjs"))
        XCTAssertTrue(storeKitRunbookText.contains("node --test supabase/functions/_shared/app_store_subscription_authority.test.mjs"))
        XCTAssertTrue(storeKitRunbookText.contains("verify the App Store Server Notification `signedPayload`"))
        XCTAssertTrue(storeKitRunbookText.contains("verify the app-submitted StoreKit `signedTransactionInfo`"))
        XCTAssertTrue(productionReadinessText.contains("App Store Server Notifications are received by `app-store-server-notifications`."))
        XCTAssertTrue(productionReadinessText.contains("StoreKit transaction claims are received by `storekit-subscription-claims`."))
        XCTAssertTrue(productionReadinessText.contains("The committed scaffold does not instantiate a service-role/admin database writer"))
        XCTAssertTrue(productionReadinessText.contains("Nested App Store transaction/renewal payloads must also be verified"))
        XCTAssertTrue(productionReadinessText.contains("Verified transaction claims still need authenticated-user resolution"))
        XCTAssertTrue(planPolicyText.contains("rejects unverified `signedPayload` input"))
        XCTAssertTrue(planPolicyText.contains("StoreKit transaction claiming starts as a separate authenticated Edge Function scaffold"))
    }

    func testSupabaseMigrationCreatesProtectedAccountAndChartTables() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migrationText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/migrations/20260609133000_initial_auth_profiles_and_charts.sql")
        )
        let appStoreSubscriptionMigrationText = try String(
            contentsOf: projectRoot
                .appendingPathComponent("supabase/migrations/20260612213658_harden_app_store_subscription_authority.sql")
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
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("provider text not null default 'none'"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("storekit_product_id text"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("storekit_original_transaction_id text"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("storekit_environment text"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("app_store_status text"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("app_store_notification_type text"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("app_store_last_transaction_id text"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("entitlement_expires_at timestamptz"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("grace_period_expires_at timestamptz"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("last_verified_at timestamptz"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("subscriptions_provider_check"))
        XCTAssertTrue(appStoreSubscriptionMigrationText.contains("subscriptions_storekit_original_transaction_id_idx"))
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
        XCTAssertTrue(productionReadinessText.contains("Subscription rows include server-owned provider, StoreKit product, original transaction, App Store status, expiration, grace, revocation, and last-verification metadata."))
        XCTAssertTrue(supabaseConfigText.contains("project_id = \"smart-chart\""))
        XCTAssertTrue(supabaseConfigText.contains("additional_redirect_urls = [\"ichart://auth-callback\"]"))
        XCTAssertTrue(supabaseConfigText.contains("enable_confirmations = true"))
        XCTAssertTrue(supabaseConfigText.contains("secure_password_change = true"))
        XCTAssertTrue(supabaseConfigText.contains("max_frequency = \"1m\""))
        XCTAssertTrue(supabaseConfigText.contains("otp_length = 6"))
        XCTAssertTrue(rlsTestText.contains("owner can insert own chart document"))
        XCTAssertTrue(rlsTestText.contains("client cannot update subscription rows"))
        XCTAssertTrue(rlsTestText.contains("owner can read server-owned subscription authority fields"))
        XCTAssertTrue(rlsTestText.contains("client cannot update app store subscription authority fields"))
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
        XCTAssertTrue(productionReadinessScriptText.contains("node --test supabase/functions/_shared/app_store_subscription_authority.test.mjs"))
        XCTAssertTrue(productionReadinessScriptText.contains("SMART_CHART_RUN_LOCAL_SUPABASE_QA"))
        XCTAssertTrue(productionReadinessScriptText.contains("scripts/run_supabase_local_qa.sh"))
        XCTAssertTrue(productionReadinessScriptText.contains("ProjectConfigurationTests|ChartCloudMergeTests|ChartLibraryStoreTests|SupabaseIntegrationTests"))
        XCTAssertTrue(productionReadinessScriptText.contains("SUPABASE_SERVICE_ROLE_KEY"))
        XCTAssertTrue(productionReadinessScriptText.contains("Manual simulator/cloud gate still required"))
    }
}
