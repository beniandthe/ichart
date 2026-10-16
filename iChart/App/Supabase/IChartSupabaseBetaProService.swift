import Foundation
import Supabase

struct IChartSupabaseBetaProService: IChartBetaProService {
    let client: SupabaseClient
    let sessionRefresher: IChartSupabaseSessionRefresher

    func fetchStatus(for ownerID: UUID) async throws -> IChartBetaProStatus {
        try await verifyOwner(ownerID)
        let status: IChartBetaProStatus = try await client.rpc("free_pro_beta_status").execute().value
        try await verifyOwner(ownerID)
        guard status.ownerID == ownerID else { throw IChartBetaProServiceError.accountChanged }
        return status
    }

    func setParticipation(_ participating: Bool, for ownerID: UUID) async throws -> IChartBetaProStatus {
        try await verifyOwner(ownerID)
        let status: IChartBetaProStatus = try await client.rpc("set_free_pro_beta_participation",
            params: ParticipationParameters(participating: participating, expectedOwnerID: ownerID)).execute().value
        try await verifyOwner(ownerID)
        guard status.ownerID == ownerID else { throw IChartBetaProServiceError.accountChanged }
        return status
    }

    private func verifyOwner(_ expectedOwner: UUID) async throws {
        let session = try await sessionRefresher.refreshIfNeeded()
        guard session.user.id == expectedOwner else { throw IChartBetaProServiceError.accountChanged }
    }

    private struct ParticipationParameters: Encodable {
        let participating: Bool
        let expectedOwnerID: UUID
        enum CodingKeys: String, CodingKey {
            case participating = "p_participating"
            case expectedOwnerID = "p_expected_owner_id"
        }
    }
}

@MainActor
extension IChartBetaProStore {
    static func live(clients: IChartSupabaseClients?) -> IChartBetaProStore {
        let service = clients.map {
            IChartSupabaseBetaProService(client: $0.dataClient,
                sessionRefresher: IChartSupabaseSessionRefresher(authClient: $0.authClient, sessionStore: $0.sessionStore))
        }
        return IChartBetaProStore(service: service)
    }

    func authStateChanged(_ authState: IChartAuthState) {
        switch authState {
        case .signedIn(let session), .passwordRecovery(let session):
            authStateChanged(ownerID: session.isEmailVerified ? session.id : nil)
        case .temporarilyOffline(let session):
            authStateChanged(ownerID: session.isEmailVerified ? session.id : nil, isOffline: true)
        case .signedOut, .pendingEmailVerification, .unconfigured:
            authStateChanged(ownerID: nil)
        }
    }
}
