import SwiftUI

@main
struct SmartChartApp: App {
    @StateObject private var store: ChartLibraryStore
    @StateObject private var authStore: IChartAuthStore
    @StateObject private var cloudSyncStore: ChartCloudSyncStore
    @StateObject private var subscriptionStore: IChartStoreKitSubscriptionStore

    init() {
        let libraryStore = ChartLibraryStore.live()
        let supabaseClients = IChartSupabaseClientFactory.liveClients()
        libraryStore.onSnapshotSaved = nil
        _store = StateObject(wrappedValue: libraryStore)
        _authStore = StateObject(wrappedValue: IChartAuthStore.live(clients: supabaseClients))
        _cloudSyncStore = StateObject(wrappedValue: ChartCloudSyncStore.live(clients: supabaseClients))
        _subscriptionStore = StateObject(wrappedValue: IChartStoreKitSubscriptionStore.live(clients: supabaseClients))

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
                .task {
                    await subscriptionStore.bootstrap()
                    store.applySubscriptionState(subscriptionStore.entitlement)
                    cloudSyncStore.authStateChanged(authStore.state)
                }
                .onChange(of: subscriptionStore.entitlement) { _, entitlement in
                    store.applySubscriptionState(entitlement)
                    cloudSyncStore.authStateChanged(authStore.state)
                }
                .onChange(of: authStore.state) { _, state in
                    cloudSyncStore.authStateChanged(state)
                    Task {
                        await subscriptionStore.refreshEntitlements()
                        store.applySubscriptionState(subscriptionStore.entitlement)
                    }
                }
                .onOpenURL { url in
                    Task {
                        await authStore.handleAuthCallback(url: url)
                        cloudSyncStore.authStateChanged(authStore.state)
                        await subscriptionStore.refreshEntitlements()
                        store.applySubscriptionState(subscriptionStore.entitlement)
                    }
                }
        }
    }
}
