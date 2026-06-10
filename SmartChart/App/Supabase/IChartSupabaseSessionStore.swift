import Foundation
import Supabase

enum IChartSupabaseSessionError: LocalizedError {
    case missingSession

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Auth session missing."
        }
    }
}

protocol IChartSupabaseSessionProviding: Sendable {
    func accessToken() async throws -> String?
    func currentUserID() async throws -> UUID
}

actor IChartSupabaseSessionStore: IChartSupabaseSessionProviding {
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

    func currentUserID() async throws -> UUID {
        guard let session else {
            throw IChartSupabaseSessionError.missingSession
        }

        return session.user.id
    }
}

struct IChartSupabaseClients {
    let authClient: SupabaseClient
    let dataClient: SupabaseClient
    let sessionStore: IChartSupabaseSessionStore
}
