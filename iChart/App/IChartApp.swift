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
        let libraryStore = ChartLibraryStore.live()
        let pdfLibraryStore = IChartPDFLibraryStore.live()
        let supabaseClients = IChartSupabaseClientFactory.liveClients()
        libraryStore.onSnapshotSaved = nil
        _store = StateObject(wrappedValue: libraryStore)
        _authStore = StateObject(wrappedValue: IChartAuthStore.live(clients: supabaseClients))
        _cloudSyncStore = StateObject(wrappedValue: ChartCloudSyncStore.live(clients: supabaseClients))
        _subscriptionStore = StateObject(wrappedValue: IChartStoreKitSubscriptionStore.live(clients: supabaseClients))
        _forumStore = StateObject(wrappedValue: IChartForumStore.live(clients: supabaseClients))
        _pdfLibraryStore = StateObject(wrappedValue: pdfLibraryStore)

        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        #endif
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
                    await subscriptionStore.bootstrap()
                    applySubscriptionState(subscriptionStore.entitlement)
                    cloudSyncStore.authStateChanged(authStore.state)
                    await forumStore.refresh(authState: authStore.state, entitlements: store.entitlements)
                }
                .onChange(of: subscriptionStore.entitlement) { _, entitlement in
                    applySubscriptionState(entitlement)
                    cloudSyncStore.authStateChanged(authStore.state)
                    Task {
                        await forumStore.refresh(authState: authStore.state, entitlements: store.entitlements)
                    }
                }
                .onChange(of: authStore.state) { _, state in
                    cloudSyncStore.authStateChanged(state)
                    Task {
                        await subscriptionStore.refreshEntitlements()
                        applySubscriptionState(subscriptionStore.entitlement)
                        await forumStore.refresh(authState: state, entitlements: store.entitlements)
                    }
                }
                .onOpenURL { url in
                    Task {
                        await authStore.handleAuthCallback(url: url)
                        cloudSyncStore.authStateChanged(authStore.state)
                        await subscriptionStore.refreshEntitlements()
                        applySubscriptionState(subscriptionStore.entitlement)
                        await forumStore.refresh(authState: authStore.state, entitlements: store.entitlements)
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
