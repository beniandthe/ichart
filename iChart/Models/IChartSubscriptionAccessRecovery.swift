import Foundation

/// Ordinary subscription access is independent of campaign-ledger confirmation.
/// Implementations must bind each request and its returned row to expectedOwnerID.
protocol IChartSubscriptionAccessClaiming: Sendable {
    func appAccountToken() async throws -> UUID?
    func claim(
        signedTransactionInfo: String,
        expectedOwnerID: UUID
    ) async throws -> IChartSubscriptionEntitlement?
    func loadRemoteSubscriptionEntitlement(
        now: Date,
        expectedOwnerID: UUID
    ) async throws -> IChartSubscriptionEntitlement?
}

enum IChartSubscriptionAccessRecovery {
    enum Source: String, Equatable {
        case ordinaryClaim = "ordinary_claim"
        case freshRemote = "fresh_remote"
    }

    enum Resolution: Equatable {
        case verified(IChartSubscriptionEntitlement, Source)
        case noRemoteSubscription
        case unavailable(claimFailed: Bool)
    }

    enum ValidationError: Error {
        case accountChanged
        case configurationUnavailable
    }

    /// No local transaction, cached entitlement, or campaign state can grant access here.
    @MainActor
    static func resolve(
        expectedOwnerID: UUID?,
        signedTransactionInfo: String?,
        service: any IChartSubscriptionAccessClaiming,
        now: Date
    ) async -> Resolution {
        guard let expectedOwnerID else { return .unavailable(claimFailed: false) }
        var claimFailed = false

        do {
            guard try await service.appAccountToken() == expectedOwnerID else {
                return .unavailable(claimFailed: false)
            }
            if let signedTransactionInfo {
                do {
                    let claimed = try await service.claim(
                        signedTransactionInfo: signedTransactionInfo,
                        expectedOwnerID: expectedOwnerID
                    )
                    guard try await service.appAccountToken() == expectedOwnerID else {
                        return .unavailable(claimFailed: true)
                    }
                    if let claimed { return .verified(claimed, .ordinaryClaim) }
                } catch {
                    claimFailed = true
                }
            }

            // A rejected/transient claim still permits a fresh authenticated read,
            // but never for an owner different from the refresh's initial owner.
            guard try await service.appAccountToken() == expectedOwnerID else {
                return .unavailable(claimFailed: claimFailed)
            }
            let remote = try await service.loadRemoteSubscriptionEntitlement(
                now: now,
                expectedOwnerID: expectedOwnerID
            )
            guard try await service.appAccountToken() == expectedOwnerID else {
                return .unavailable(claimFailed: claimFailed)
            }
            if let remote { return .verified(remote, .freshRemote) }
            return .noRemoteSubscription
        } catch {
            return .unavailable(claimFailed: claimFailed)
        }
    }

    /// Validate the actual bearer-session owner and returned row, not only owners
    /// sampled around awaits (which would miss an A -> B -> A request).
    static func validatedEntitlement(
        record: IChartRemoteSubscriptionRecord?,
        expectedOwnerID: UUID,
        authenticatedRequestOwnerID: UUID,
        currentOwnerID: UUID?,
        accepted: Bool = true,
        now: Date
    ) throws -> IChartSubscriptionEntitlement? {
        guard authenticatedRequestOwnerID == expectedOwnerID,
              currentOwnerID == expectedOwnerID,
              record == nil || record?.ownerID == expectedOwnerID else {
            throw ValidationError.accountChanged
        }
        guard accepted else { return nil }
        return record?.entitlement(now: now)
    }
}
