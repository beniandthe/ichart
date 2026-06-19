import Foundation
import Supabase

actor IChartSupabaseSessionStore {
    private var session: Session?

    func update(_ session: Session) {
        self.session = session
    }

    func clear() {
        session = nil
    }

    func accessToken() async throws -> String? {
        session?.accessToken
    }
}

struct IChartSupabaseSessionRefresher {
    private let authClient: SupabaseClient
    private let sessionStore: IChartSupabaseSessionStore
    private let persistentSessionStore: IChartSupabasePersistentSessionStore

    init(
        authClient: SupabaseClient,
        sessionStore: IChartSupabaseSessionStore,
        persistentSessionStore: IChartSupabasePersistentSessionStore = IChartSupabasePersistentSessionStore()
    ) {
        self.authClient = authClient
        self.sessionStore = sessionStore
        self.persistentSessionStore = persistentSessionStore
    }

    @discardableResult
    func refreshIfNeeded() async throws -> Session {
        let session = try await authClient.auth.session
        try persistentSessionStore.store(session)
        await sessionStore.update(session)
        return session
    }
}

struct IChartSupabaseClients {
    let authClient: SupabaseClient
    let dataClient: SupabaseClient
    let sessionStore: IChartSupabaseSessionStore
}
