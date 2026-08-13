import SwiftUI

@main
struct IChartApp: App {
    @StateObject private var store: ChartLibraryStore
    @StateObject private var authStore: IChartAuthStore
    @StateObject private var cloudSyncStore: ChartCloudSyncStore
    @StateObject private var subscriptionStore: IChartStoreKitSubscriptionStore
    @StateObject private var forumStore: IChartForumStore
    @StateObject private var pdfLibraryStore: IChartPDFLibraryStore

    init() {
        let appInitSpan = IChartPerformanceTrace.start("app.init")
        let libraryStore = ChartLibraryStore.live()
        let pdfLibraryStore = IChartPDFLibraryStore.live()
        let supabaseClients = IChartSupabaseClientFactory.liveClients()
        IChartTelemetry.configure(IChartTelemetryService.live(clients: supabaseClients))
        IChartTelemetry.record(
            "app.launched",
            properties: [
                "app_phase": .string("init"),
                "chart_count": .int(libraryStore.charts.count),
                "project_count": .int(libraryStore.projects.count)
            ]
        )
        libraryStore.onSnapshotSaved = nil
        _store = StateObject(wrappedValue: libraryStore)
        _authStore = StateObject(wrappedValue: IChartAuthStore.live(clients: supabaseClients))
        _cloudSyncStore = StateObject(wrappedValue: ChartCloudSyncStore.live(clients: supabaseClients))
        _subscriptionStore = StateObject(wrappedValue: IChartStoreKitSubscriptionStore.live(clients: supabaseClients))
        _forumStore = StateObject(wrappedValue: IChartForumStore.live(clients: supabaseClients))
        _pdfLibraryStore = StateObject(wrappedValue: pdfLibraryStore)

        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        NotationGlyphPathCache.scheduleDefaultLeadSheetWarmup()
        #endif

        IChartPerformanceTrace.end(appInitSpan)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .environmentObject(authStore)
                .environmentObject(cloudSyncStore)
                .environmentObject(subscriptionStore)
                .environmentObject(forumStore)
                .environmentObject(pdfLibraryStore)
                .task {
                    let bootstrapSpan = IChartPerformanceTrace.start("app.bootstrap")
                    await subscriptionStore.bootstrap()
                    IChartPerformanceTrace.record("app.bootstrap.subscriptionStore.complete")
                    applySubscriptionState(subscriptionStore.entitlement)
                    cloudSyncStore.authStateChanged(authStore.state)
                    IChartPerformanceTrace.end(bootstrapSpan)
                    IChartTelemetry.record(
                        "app.bootstrap_completed",
                        properties: [
                            "auth_state": .string(authStore.state.telemetryValue),
                            "plan": .string(subscriptionStore.entitlement.effectivePlan.rawValue),
                            "subscription_status": .string(subscriptionStore.entitlement.status.rawValue)
                        ]
                    )
                    IChartTelemetry.flush()
                }
                .onChange(of: subscriptionStore.entitlement) { _, entitlement in
                    applySubscriptionState(entitlement)
                    cloudSyncStore.authStateChanged(authStore.state)
                    IChartTelemetry.record(
                        "subscription.entitlement_changed",
                        properties: [
                            "plan": .string(entitlement.effectivePlan.rawValue),
                            "subscription_status": .string(entitlement.status.rawValue)
                        ]
                    )
                }
                .onChange(of: authStore.state) { _, state in
                    cloudSyncStore.authStateChanged(state)
                    IChartTelemetry.record(
                        "auth.state_changed",
                        properties: [
                            "auth_state": .string(state.telemetryValue),
                            "user_signed_in": .bool(state.signedInSession != nil)
                        ]
                    )
                    Task {
                        await subscriptionStore.refreshEntitlements()
                        applySubscriptionState(subscriptionStore.entitlement)
                        IChartTelemetry.flush()
                    }
                }
                .onOpenURL { url in
                    if IChartSupabaseClientFactory.isAuthCallbackURL(url) {
                        IChartTelemetry.record(
                            "auth.callback_received",
                            properties: [
                                "flow": .string(url.telemetryAuthFlow),
                                "source": .string("url_open")
                            ]
                        )
                    }
                    Task {
                        await authStore.handleAuthCallback(url: url)
                        cloudSyncStore.authStateChanged(authStore.state)
                        await subscriptionStore.refreshEntitlements()
                        applySubscriptionState(subscriptionStore.entitlement)
                        IChartTelemetry.flush()
                    }
                }
        }
    }

    private func applySubscriptionState(_ entitlement: IChartSubscriptionEntitlement) {
        let resolvedEntitlement = entitlement.resolvedForLibraryApplication(
            currentLibraryEntitlement: store.entitlements.subscription
        )
        store.applySubscriptionState(resolvedEntitlement)
        pdfLibraryStore.removeForumDownloadsIfInactive(for: resolvedEntitlement)
    }
}

private extension URL {
    var telemetryAuthFlow: String {
        if let type = URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "type" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !type.isEmpty {
            return type
        }

        return "unknown"
    }
}
