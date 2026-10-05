import Foundation

enum RecognitionStudyConsentWithdrawalCoordinatorError: Error, Equatable {
    case noWithdrawalIntent
    case operationAlreadyInProgress
}

protocol RecognitionStudyConsentWithdrawing: Sendable {
    func withdraw(
        consentRecordID: UUID,
        clientRequestID: UUID,
        accessToken: String
    ) async throws -> RecognitionStudyConsentResponse
}

extension RecognitionStudyConsentHTTPClient:
    RecognitionStudyConsentWithdrawing {}

/// Persists withdrawal before doing network work and makes local raw-capture
/// deletion part of every initial or resumed attempt.
///
/// The durable intent stores only the consent-record and idempotency UUIDs. It
/// never stores an access token. The upload store's barrier prevents new queued
/// capture work both while the server is unavailable and after acknowledgement.
/// This coordinator intentionally has no UI, auth, scheduling, or automatic
/// retry policy; those require a separately reviewed app lifecycle.
actor RecognitionStudyConsentWithdrawalCoordinator {
    typealias AccessTokenProvider =
        @Sendable () async throws -> String

    private let store: RecognitionStudyPendingCaptureUploadStore
    private let consentWithdrawer: any RecognitionStudyConsentWithdrawing
    private var operationIsInProgress = false

    init(
        store: RecognitionStudyPendingCaptureUploadStore,
        consentWithdrawer: any RecognitionStudyConsentWithdrawing
    ) {
        self.store = store
        self.consentWithdrawer = consentWithdrawer
    }

    /// Installs the barrier and purges local raw upload data before the first
    /// cancellation check or access-token lookup. A failed network attempt is
    /// therefore safely resumable without reopening collection.
    func requestWithdrawal(
        consentRecordID: UUID,
        clientRequestID: UUID,
        accessTokenProvider: @escaping AccessTokenProvider
    ) async throws -> RecognitionStudyConsentResponse {
        try beginOperation()
        defer { operationIsInProgress = false }

        let intent = try await store.registerWithdrawalBarrierAndPurge(
            consentRecordID: consentRecordID,
            clientRequestID: clientRequestID
        )
        return try await submitPendingIntent(
            intent,
            accessTokenProvider: accessTokenProvider
        )
    }

    /// Reapplies local deletion before retrying the exact durable idempotency
    /// identity. An acknowledged intent returns its stored validated response
    /// without another token lookup or request.
    func resumeWithdrawal(
        accessTokenProvider: @escaping AccessTokenProvider
    ) async throws -> RecognitionStudyConsentResponse {
        try beginOperation()
        defer { operationIsInProgress = false }

        try await store.purgeAllPendingAndQuarantinedData()
        switch try await store.withdrawalBarrierState() {
        case .none:
            throw RecognitionStudyConsentWithdrawalCoordinatorError
                .noWithdrawalIntent
        case .pending(let intent):
            return try await submitPendingIntent(
                intent,
                accessTokenProvider: accessTokenProvider
            )
        case .acknowledged(_, let response):
            return response
        }
    }

    private func submitPendingIntent(
        _ intent: RecognitionStudyPendingConsentWithdrawal,
        accessTokenProvider: @escaping AccessTokenProvider
    ) async throws -> RecognitionStudyConsentResponse {
        switch try await store.withdrawalBarrierState() {
        case .pending(let currentIntent) where currentIntent == intent:
            break
        case .acknowledged(let currentIntent, let response)
                where currentIntent == intent:
            return response
        default:
            throw RecognitionStudyPendingCaptureUploadStoreError
                .withdrawalIntentConflict
        }
        try Task.checkCancellation()
        let accessToken = try await accessTokenProvider()
        try Task.checkCancellation()

        switch try await store.withdrawalBarrierState() {
        case .pending(let currentIntent) where currentIntent == intent:
            break
        case .acknowledged(let currentIntent, let response)
                where currentIntent == intent:
            return response
        default:
            throw RecognitionStudyPendingCaptureUploadStoreError
                .withdrawalIntentConflict
        }
        let response = try await consentWithdrawer.withdraw(
            consentRecordID: intent.consentRecordID.uuid,
            clientRequestID: intent.clientRequestID.uuid,
            accessToken: accessToken
        )
        // A validated server acknowledgement and its durable local transition
        // are one logical boundary. Do not turn task cancellation into an
        // unnecessary replay between those two steps.
        try await store.markWithdrawalAcknowledged(response, for: intent)
        return response
    }

    private func beginOperation() throws {
        guard !operationIsInProgress else {
            throw RecognitionStudyConsentWithdrawalCoordinatorError
                .operationAlreadyInProgress
        }
        operationIsInProgress = true
    }
}
