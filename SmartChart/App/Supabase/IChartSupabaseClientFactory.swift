import Foundation
import Supabase

enum IChartSupabaseClientFactory {
    static let authCallbackURL = URL(string: "ichart://auth-callback")!

    static func isAuthCallbackURL(_ url: URL) -> Bool {
        url.scheme == authCallbackURL.scheme && url.host == authCallbackURL.host
    }

    static func liveClient() -> SupabaseClient? {
        guard let configuration = IChartSupabaseConfiguration.current() else {
            return nil
        }

        return SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: IChartSupabaseAuthLocalStorage(),
                    redirectToURL: authCallbackURL
                )
            )
        )
    }
}
