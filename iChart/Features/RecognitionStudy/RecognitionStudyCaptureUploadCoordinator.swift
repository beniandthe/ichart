import Foundation

enum RecognitionStudyCaptureUploadCoordinatorError: Error, Equatable {
    case operationAlreadyInProgress
}

protocol RecognitionStudyPreparedCaptureUploading: Sendable {
    func uploadPreparedCapture(
        _ preparedUpload: RecognitionStudyPreparedCaptureUpload,
        accessToken: String
    ) async throws -> RecognitionStudyCaptureReceipt
}

extension RecognitionStudyCaptureHTTPClient:
    RecognitionStudyPreparedCaptureUploading {}

struct RecognitionStudyCaptureUploadFlushResult: Equatable, Sendable {
    let acknowledgedReceipts: [RecognitionStudyCaptureReceipt]
    let remainingCaptureCount: Int
}

/// Coordinates the credential-free durable queue with the injected transport.
///
/// Every new capture is committed to protected storage before network access.
/// A fresh access token is requested for each attempt but is never retained by
/// this actor or the queue. Uploads leave the queue only after the server returns
/// a receipt whose capture, envelope, and packet bindings have been validated.
///
/// This type intentionally performs no automatic retry, background scheduling,
/// authentication, consent presentation, or UI wiring. A reviewed caller must
/// decide when network activity is appropriate and provide each transient token.
actor RecognitionStudyCaptureUploadCoordinator {
    typealias AccessTokenProvider =
        @Sendable () async throws -> String

    private let store: RecognitionStudyPendingCaptureUploadStore
    private let uploader: any RecognitionStudyPreparedCaptureUploading
    private var operationIsInProgress = false

    init(
        store: RecognitionStudyPendingCaptureUploadStore,
        uploader: any RecognitionStudyPreparedCaptureUploading
    ) {
        self.store = store
        self.uploader = uploader
    }

    /// Durably enqueues `upload` before attempting any pending network work.
    /// Older pending captures are sent first using the store's stable order.
    func enqueueAndFlush(
        _ upload: RecognitionStudyPreparedCaptureUpload,
        enqueuedAtUnixMilliseconds: Int64,
        accessTokenProvider: @escaping AccessTokenProvider
    ) async throws -> RecognitionStudyCaptureUploadFlushResult {
        try beginOperation()
        defer { operationIsInProgress = false }

        try await store.requireUploadsPermitted()
        _ = try await store.enqueue(
            upload,
            enqueuedAtUnixMilliseconds: enqueuedAtUnixMilliseconds
        )
        return try await flushPendingWithoutOperationGuard(
            accessTokenProvider: accessTokenProvider
        )
    }

    /// Attempts the finite pending snapshot once. The first failed or cancelled
    /// attempt stops the pass, while already acknowledged captures stay removed
    /// and the failed capture plus all later captures remain durable.
    func flushPending(
        accessTokenProvider: @escaping AccessTokenProvider
    ) async throws -> RecognitionStudyCaptureUploadFlushResult {
        try beginOperation()
        defer { operationIsInProgress = false }
        return try await flushPendingWithoutOperationGuard(
            accessTokenProvider: accessTokenProvider
        )
    }

    /// Local privacy boundary for a separately reviewed withdrawal or account
    /// deletion flow. It refuses to race an in-flight upload operation.
    func purgePendingAndQuarantinedData() async throws {
        try beginOperation()
        defer { operationIsInProgress = false }
        try await store.purgeAllPendingAndQuarantinedData()
    }

    private func beginOperation() throws {
        guard !operationIsInProgress else {
            throw RecognitionStudyCaptureUploadCoordinatorError
                .operationAlreadyInProgress
        }
        operationIsInProgress = true
    }

    private func flushPendingWithoutOperationGuard(
        accessTokenProvider: @escaping AccessTokenProvider
    ) async throws -> RecognitionStudyCaptureUploadFlushResult {
        try Task.checkCancellation()
        try await store.requireUploadsPermitted()
        let pendingSnapshot = try await store.pendingUploads()
        var receipts: [RecognitionStudyCaptureReceipt] = []
        receipts.reserveCapacity(pendingSnapshot.count)

        for upload in pendingSnapshot {
            try Task.checkCancellation()
            try await store.requireUploadsPermitted()
            let accessToken = try await accessTokenProvider()
            try Task.checkCancellation()
            try await store.requireUploadsPermitted()
            let receipt = try await uploader.uploadPreparedCapture(
                upload,
                accessToken: accessToken
            )
            // Do not check cancellation between receiving a valid receipt and
            // committing its acknowledgement. That transition must complete or
            // remain safely replayable after a storage failure.
            try await store.removeAcknowledged(by: receipt)
            receipts.append(receipt)
        }

        return RecognitionStudyCaptureUploadFlushResult(
            acknowledgedReceipts: receipts,
            remainingCaptureCount: try await store.pendingUploads().count
        )
    }
}
