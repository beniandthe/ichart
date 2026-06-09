import SwiftUI

@main
struct SmartChartApp: App {
    @StateObject private var store = ChartLibraryStore.live()
    @StateObject private var authStore = IChartAuthStore.live()

    init() {
        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .environmentObject(authStore)
        }
    }
}
