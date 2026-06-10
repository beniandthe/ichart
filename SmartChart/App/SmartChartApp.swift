import SwiftUI

@main
struct SmartChartApp: App {
    @StateObject private var store: ChartLibraryStore
    @StateObject private var authStore: IChartAuthStore
    @StateObject private var cloudSyncStore: ChartCloudSyncStore

    init() {
        let libraryStore = ChartLibraryStore.live()
        let supabaseClients = IChartSupabaseClientFactory.liveClients()
        libraryStore.onSnapshotSaved = nil
        _store = StateObject(wrappedValue: libraryStore)
        _authStore = StateObject(wrappedValue: IChartAuthStore.live(clients: supabaseClients))
        _cloudSyncStore = StateObject(wrappedValue: ChartCloudSyncStore.live(clients: supabaseClients))

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
                .onOpenURL { url in
                    Task {
                        await authStore.handleAuthCallback(url: url)
                        cloudSyncStore.authStateChanged(authStore.state)
                    }
                }
        }
    }
}
