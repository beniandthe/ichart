import Foundation
import Supabase

enum IChartSupabaseClientFactory {
    static let authCallbackURL = URL(string: "ichart://auth-callback")!

    static func isAuthCallbackURL(_ url: URL) -> Bool {
        url.scheme == authCallbackURL.scheme && url.host == authCallbackURL.host
    }

    static func liveClients() -> IChartSupabaseClients? {
        guard let configuration = IChartSupabaseConfiguration.current() else {
            return nil
        }

        let sessionStore = IChartSupabaseSessionStore()
        let authClient = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: IChartSupabaseAuthLocalStorage(),
                    redirectToURL: authCallbackURL
                )
            )
        )
        let dataClient = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: IChartSupabaseAuthLocalStorage(),
                    redirectToURL: authCallbackURL,
                    accessToken: {
                        try await sessionStore.accessToken()
                    }
                )
            )
        )

        return IChartSupabaseClients(
            authClient: authClient,
            dataClient: dataClient,
            sessionStore: sessionStore
        )
    }
}
