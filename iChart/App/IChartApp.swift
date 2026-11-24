import SwiftUI

@main
struct IChartApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: ChartLibraryStore
    @StateObject private var authStore: IChartAuthStore
    @StateObject private var cloudSyncStore: ChartCloudSyncStore
    @StateObject private var subscriptionStore: IChartStoreKitSubscriptionStore
    @StateObject private var betaProStore: IChartBetaProStore
    @StateObject private var forumStore: IChartForumStore
    @StateObject private var pdfLibraryStore: IChartPDFLibraryStore
    @StateObject private var setlistStore: IChartPDFSetlistStore
    @StateObject private var setlistCloudSyncStore: IChartPDFSetlistCloudSyncStore

    init() {
        let initializationStartedAt = ProcessInfo.processInfo.systemUptime
        let appInitSpan = IChartPerformanceTrace.start("app.init")
        let supabaseClients = IChartSupabaseClientFactory.liveClients()
        let libraryStore = ChartLibraryStore.live()
        let pdfLibraryStore = IChartPDFLibraryStore.live()
        let setlistStore = IChartPDFSetlistStore.live()
        let setlistCloudSyncStore = IChartPDFSetlistCloudSyncStore.live(clients: supabaseClients)
        setlistCloudSyncStore.attach(setlistStore: setlistStore, pdfStore: pdfLibraryStore)
        libraryStore.onSnapshotSaved = nil
        _store = StateObject(wrappedValue: libraryStore)
        _authStore = StateObject(wrappedValue: IChartAuthStore.live(clients: supabaseClients))
        _cloudSyncStore = StateObject(wrappedValue: ChartCloudSyncStore.live(clients: supabaseClients))
        _subscriptionStore = StateObject(wrappedValue: IChartStoreKitSubscriptionStore.live(clients: supabaseClients))
        _betaProStore = StateObject(wrappedValue: IChartBetaProStore.live(clients: supabaseClients))
        _forumStore = StateObject(wrappedValue: IChartForumStore.live(clients: supabaseClients))
        _pdfLibraryStore = StateObject(wrappedValue: pdfLibraryStore)
        _setlistStore = StateObject(wrappedValue: setlistStore)
        _setlistCloudSyncStore = StateObject(wrappedValue: setlistCloudSyncStore)

        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        NotationGlyphPathCache.scheduleDefaultLeadSheetWarmup()
        #endif

        IChartPerformanceTrace.end(appInitSpan)
        let initializationMilliseconds = (ProcessInfo.processInfo.systemUptime - initializationStartedAt) * 1_000
        let libraryLoadOutcome = libraryStore.initialLoadOutcome
        // Optional diagnostics begin after the app's stores exist. Construction,
        // consent preferences, old queue migration, disk I/O and network work
        // all stay on this utility task; launch never awaits them.
        Task.detached(priority: .utility) {
            guard let telemetry = IChartTelemetryService.live(clients: supabaseClients) else { return }
            IChartTelemetry.configure(telemetry)
            await telemetry.initialize()
            if let libraryLoadOutcome {
                ChartLibraryStore.recordBasicLoadOutcome(libraryLoadOutcome)
            }
            IChartTelemetry.record("app.launched", properties: [
                "duration_ms": .double(initializationMilliseconds)
            ])
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.hasUnresolvedLoadFailure {
                    IChartLibraryLoadRecoveryView {
                        if store.retryLoadingSavedSnapshot() {
                            synchronizeBetaAccess(authStore.state)
                            applySubscriptionState(subscriptionStore.entitlement)
                            cloudSyncStore.authStateChanged(authStore.state)
                        }
                    }
                } else {
                    AppRootView()
                }
            }
                #if ICHART_STAGING_STOREKIT_PRODUCTS
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Internal staging")
                            .font(.caption.weight(.semibold))
                        Text("Separate QA charts, PDFs and account. Your public app data stays separate.")
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .accessibilityElement(children: .combine)
                }
                #endif
                .environmentObject(store)
                .environmentObject(authStore)
                .environmentObject(cloudSyncStore)
                .environmentObject(subscriptionStore)
                .environmentObject(forumStore)
                .environmentObject(pdfLibraryStore)
                .environmentObject(setlistStore)
                .environment(
                    \.setlistCloudSyncStore,
                    IChartProductAccessPolicy.current.offersPaidPurchases ? setlistCloudSyncStore : nil
                )
                .environment(\.betaProStore, betaProStore)
                .environment(\.betaProRetryAction, { await retryBetaAccess() })
                .modifier(IChartBetaProNoticePresenter(store: betaProStore))
                .task {
                    let bootstrapStartedAt = ProcessInfo.processInfo.systemUptime
                    let bootstrapSpan = IChartPerformanceTrace.start("app.bootstrap")
                    synchronizeBetaAccess(authStore.state)
                    await retryBetaAccess()
                    await subscriptionStore.bootstrap()
                    IChartPerformanceTrace.record("app.bootstrap.subscriptionStore.complete")
                    applySubscriptionState(subscriptionStore.entitlement)
                    cloudSyncStore.authStateChanged(authStore.state)
                    IChartPerformanceTrace.end(bootstrapSpan)
                    IChartTelemetry.record(
                        "app.bootstrap_completed",
                        properties: [
                            "duration_ms": .double((ProcessInfo.processInfo.systemUptime - bootstrapStartedAt) * 1_000)
                        ]
                    )
                    IChartTelemetry.flush()
                }
                .onChange(of: subscriptionStore.entitlement) { _, entitlement in
                    applySubscriptionState(entitlement)
                    cloudSyncStore.authStateChanged(authStore.state)
                }
                .onChange(of: subscriptionStore.verifiedSubscriptionOwnerID) { _, _ in
                    synchronizeSetlistCloudAccess()
                }
                .onChange(of: betaProStore.freeProAccess) { _, _ in
                    applyBetaAccessPolicy()
                    cloudSyncStore.authStateChanged(authStore.state)
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else {
                        return
                    }
                    IChartSimulatorPreviewLaunch.applyEditorFixtureOrientation()
                    synchronizeBetaAccess(authStore.state)
                    await retryBetaAccess()
                    if IChartProductAccessPolicy.current.offersPaidPurchases,
                       subscriptionStore.state != .idle, !subscriptionStore.state.isWorking {
                        await subscriptionStore.refreshEntitlements()
                        applySubscriptionState(subscriptionStore.entitlement)
                    }
                    // One best-effort request; optional delivery is never an
                    // awaited foreground loop or an app-readiness condition.
                    IChartTelemetry.flush()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        // Best effort before suspension; unacknowledged events
                        // stay on disk and retry on the next active session.
                        IChartTelemetry.flush()
                    }
                }
                .onChange(of: authStore.state) { _, state in
                    // Apply the new account's choice before scheduling cloud work.
                    synchronizeBetaAccess(state)
                    cloudSyncStore.authStateChanged(state)
                    synchronizeSetlistCloudAccess()
                    Task {
                        await retryBetaAccess()
                        await subscriptionStore.refreshEntitlements()
                        applySubscriptionState(subscriptionStore.entitlement)
                        IChartTelemetry.flush()
                    }
                }
                .onOpenURL { url in
                    Task {
                        await authStore.handleAuthCallback(url: url)
                        synchronizeBetaAccess(authStore.state)
                        cloudSyncStore.authStateChanged(authStore.state)
                        await retryBetaAccess()
                        await subscriptionStore.refreshEntitlements()
                        applySubscriptionState(subscriptionStore.entitlement)
                        IChartTelemetry.flush()
                    }
                }
        }
    }

    private func synchronizeBetaAccess(_ state: IChartAuthState) {
        guard IChartProductAccessPolicy.current.isFreeBeta else { return }
        betaProStore.authStateChanged(state)
        applyBetaAccessPolicy()
    }

    @MainActor
    private func retryBetaAccess() async {
        guard IChartProductAccessPolicy.current.isFreeBeta else { return }
        await betaProStore.retryAfterSessionRecovery {
            if case .temporarilyOffline = authStore.state, !authStore.isWorking {
                await authStore.refreshSession()
            }
            // A real recovered session must select its own cached access policy
            // before cloud observes the account. Failed reconnects remain offline.
            synchronizeBetaAccess(authStore.state)
            cloudSyncStore.authStateChanged(authStore.state)
        }
    }

    private func applyBetaAccessPolicy() {
        guard IChartProductAccessPolicy.current.isFreeBeta else { return }
        store.applyAccessPolicy(betaProStore.freeProAccess ? .freeAllFeatures : .betaBasic)
    }

    private func applySubscriptionState(_ entitlement: IChartSubscriptionEntitlement) {
        guard !store.hasUnresolvedLoadFailure else { return }
        let resolvedEntitlement = entitlement.resolvedForLibraryApplication(
            currentLibraryEntitlement: store.entitlements.subscription
        )
        store.applySubscriptionState(resolvedEntitlement)
        synchronizeSetlistCloudAccess()
    }

    private func synchronizeSetlistCloudAccess() {
        let session: IChartAccountSession?
        let online: Bool
        switch authStore.state {
        case .signedIn(let account):
            session = account
            online = true
        case .temporarilyOffline(let account):
            session = account
            online = false
        default:
            session = nil
            online = false
        }

        let ownerID = session?.isEmailVerified == true ? session?.id : nil
        let canSync = ownerID != nil
            && ownerID == subscriptionStore.verifiedSubscriptionOwnerID
            && subscriptionStore.entitlement.status == .proActive
            && store.entitlements.canSyncPDFSetlists
        setlistCloudSyncStore.updateAccess(ownerID: ownerID, canSync: canSync, isOnline: online)
    }
}

struct IChartLibraryLoadRecoveryView: View {
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
                    .accessibilityHidden(true)

                Text("Your Saved Library Couldn’t Be Opened")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Editing and cloud sync are paused to protect your saved charts. Retry loading your saved library; your saved file has not been replaced.")
                    .multilineTextAlignment(.center)

                Button("Retry Loading", action: retry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("libraryLoadRetry")

                Text("If loading still fails, keep this installation and contact support@useichart.com.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 480)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("libraryLoadRecovery")
    }
}
