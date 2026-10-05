import Foundation

enum RecognitionStudyPendingCaptureUploadStoreError: Error, Equatable {
    case protectedDataUnavailable
    case invalidQuotaConfiguration(String)
    case quotaExceeded(field: String, maximum: UInt64, actual: UInt64)
    case captureConflict(String)
    case captureNotFound(String)
    case withdrawalBarrierActive
    case withdrawalIntentConflict
    case corruptArtifact(String)
}

struct RecognitionStudyPendingConsentWithdrawal:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let currentSchemaVersion =
        "recognition-study-pending-consent-withdrawal-v1"
    static let maximumCanonicalJSONByteCount = 4 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let clientRequestID: RecognitionStudyCanonicalUUID
    let consentRecordID: RecognitionStudyCanonicalUUID

    init(clientRequestID: UUID, consentRecordID: UUID) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        self.clientRequestID = RecognitionStudyCanonicalUUID(clientRequestID)
        self.consentRecordID = RecognitionStudyCanonicalUUID(consentRecordID)
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: Wire.self,
            construct: { try Self(wire: $0) }
        )
    }

    func validateContract() throws {
        guard schemaVersion.rawValue == Self.currentSchemaVersion else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("withdrawal intent schema")
        }
    }

    private init(wire: Wire) throws {
        schemaVersion = wire.schemaVersion
        clientRequestID = wire.clientRequestID
        consentRecordID = wire.consentRecordID
        try validateContract()
    }

    private struct Wire: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let clientRequestID: RecognitionStudyCanonicalUUID
        let consentRecordID: RecognitionStudyCanonicalUUID
    }
}

enum RecognitionStudyConsentWithdrawalBarrierState: Equatable, Sendable {
    case none
    case pending(RecognitionStudyPendingConsentWithdrawal)
    case acknowledged(
        RecognitionStudyPendingConsentWithdrawal,
        RecognitionStudyConsentResponse
    )
}

enum RecognitionStudyPendingCaptureUploadStoreFaultPoint: String, Sendable {
    case afterPayloadSynchronizationBeforePromotion
    case afterCommitSynchronizationBeforePromotion
    case afterAcknowledgedMoveBeforeRemoval
}

enum RecognitionStudyPendingCaptureUploadStorePolicyRequest:
    Equatable,
    Sendable
{
    case completeFileProtection(URL)
    case excludeFromBackup(URL)
    case synchronize(URL)
}

struct RecognitionStudyPendingCaptureUploadStoreHooks: Sendable {
    var isProtectedDataAvailable: @Sendable () -> Bool
    var classifiesProtectedDataError: @Sendable (Error) -> Bool
    var observePolicyRequest:
        @Sendable (
            RecognitionStudyPendingCaptureUploadStorePolicyRequest
        ) -> Void
    var injectFault:
        @Sendable (
            RecognitionStudyPendingCaptureUploadStoreFaultPoint
        ) throws -> Void

    init(
        isProtectedDataAvailable: @escaping @Sendable () -> Bool = { true },
        classifiesProtectedDataError:
            @escaping @Sendable (Error) -> Bool = { error in
                let nsError = error as NSError
                guard nsError.domain == NSCocoaErrorDomain else {
                    return false
                }
                return nsError.code
                    == CocoaError.Code.fileReadNoPermission.rawValue
                    || nsError.code
                        == CocoaError.Code.fileWriteNoPermission.rawValue
            },
        observePolicyRequest:
            @escaping @Sendable (
                RecognitionStudyPendingCaptureUploadStorePolicyRequest
            ) -> Void = { _ in },
        injectFault:
            @escaping @Sendable (
                RecognitionStudyPendingCaptureUploadStoreFaultPoint
            ) throws -> Void = { _ in }
    ) {
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.classifiesProtectedDataError = classifiesProtectedDataError
        self.observePolicyRequest = observePolicyRequest
        self.injectFault = injectFault
    }
}

struct RecognitionStudyPendingCaptureUploadStoreQuotas:
    Equatable,
    Sendable
{
    static let maximumContractPendingCount: UInt32 = 256
    static let maximumContractStoreByteCount: UInt64 = 128 * 1024 * 1024

    static let contract = Self(
        uncheckedMaximumPendingCount: maximumContractPendingCount,
        maximumStoreByteCount: maximumContractStoreByteCount
    )

    let maximumPendingCount: UInt32
    let maximumStoreByteCount: UInt64

    init(
        maximumPendingCount: UInt32,
        maximumStoreByteCount: UInt64
    ) throws {
        guard maximumPendingCount > 0,
              maximumPendingCount <= Self.maximumContractPendingCount else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .invalidQuotaConfiguration("maximumPendingCount")
        }
        guard maximumStoreByteCount > 0,
              maximumStoreByteCount
                <= Self.maximumContractStoreByteCount else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .invalidQuotaConfiguration("maximumStoreByteCount")
        }
        self.maximumPendingCount = maximumPendingCount
        self.maximumStoreByteCount = maximumStoreByteCount
    }

    private init(
        uncheckedMaximumPendingCount: UInt32,
        maximumStoreByteCount: UInt64
    ) {
        maximumPendingCount = uncheckedMaximumPendingCount
        self.maximumStoreByteCount = maximumStoreByteCount
    }
}

/// Crash-safe, credential-free persistence for exact authorized upload bytes.
///
/// The queue cannot create or alter a grant, packet, envelope, label, writer
/// identity, or access token. A receipt-bound acknowledgement moves an item
/// out of the retry set before deletion, so a crash is either an exact replay
/// or a completed removal. Deletion is logical filesystem removal, not a claim
/// of forensic erasure from flash or operating-system snapshots.
actor RecognitionStudyPendingCaptureUploadStore {
    static let storeDirectoryName =
        "recognition-study-pending-capture-uploads-v1"

    private static let pendingDirectoryName = "pending"
    private static let stagingDirectoryName = "staging"
    private static let acknowledgedDirectoryName = "acknowledged"
    private static let quarantineDirectoryName = "quarantine"
    private static let withdrawalDirectoryName = "withdrawal"
    private static let requestFileName = "upload-request.json"
    private static let envelopeFileName = "envelope.json"
    private static let packetFileName = "trajectory.json"
    private static let commitFileName = "commit.json"
    private static let withdrawalIntentFileName = "intent.json"
    private static let withdrawalAcknowledgementFileName =
        "acknowledgement.json"

    private let fileManager = FileManager()
    private let hooks: RecognitionStudyPendingCaptureUploadStoreHooks
    private let quotas: RecognitionStudyPendingCaptureUploadStoreQuotas
    private let storeDirectory: URL
    private let pendingDirectory: URL
    private let stagingDirectory: URL
    private let acknowledgedDirectory: URL
    private let quarantineDirectory: URL
    private let withdrawalDirectory: URL
    private var hasStarted = false

    private init(
        rootDirectory: URL,
        hooks: RecognitionStudyPendingCaptureUploadStoreHooks,
        quotas: RecognitionStudyPendingCaptureUploadStoreQuotas
    ) {
        self.hooks = hooks
        self.quotas = quotas
        storeDirectory = rootDirectory.appendingPathComponent(
            Self.storeDirectoryName,
            isDirectory: true
        )
        pendingDirectory = storeDirectory.appendingPathComponent(
            Self.pendingDirectoryName,
            isDirectory: true
        )
        stagingDirectory = storeDirectory.appendingPathComponent(
            Self.stagingDirectoryName,
            isDirectory: true
        )
        acknowledgedDirectory = storeDirectory.appendingPathComponent(
            Self.acknowledgedDirectoryName,
            isDirectory: true
        )
        quarantineDirectory = storeDirectory.appendingPathComponent(
            Self.quarantineDirectoryName,
            isDirectory: true
        )
        withdrawalDirectory = storeDirectory.appendingPathComponent(
            Self.withdrawalDirectoryName,
            isDirectory: true
        )
    }

    static func open(
        rootDirectory: URL,
        hooks: RecognitionStudyPendingCaptureUploadStoreHooks = .init(),
        quotas: RecognitionStudyPendingCaptureUploadStoreQuotas = .contract
    ) async throws -> RecognitionStudyPendingCaptureUploadStore {
        let store = RecognitionStudyPendingCaptureUploadStore(
            rootDirectory: rootDirectory,
            hooks: hooks,
            quotas: quotas
        )
        try await store.start()
        return store
    }

    func enqueue(
        _ upload: RecognitionStudyPreparedCaptureUpload,
        enqueuedAtUnixMilliseconds: Int64
    ) throws -> RecognitionStudyPreparedCaptureUpload {
        try refreshBeforeOperation()
        try requireUploadsPermittedWithoutRefresh()
        guard enqueuedAtUnixMilliseconds >= 0,
              enqueuedAtUnixMilliseconds <= 9_007_199_254_740_991 else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("enqueuedAtUnixMilliseconds")
        }

        let captureID = upload.captureAuthorizationID.rawValue
        let finalDirectory = pendingURL(captureID)
        if fileManager.fileExists(atPath: finalDirectory.path) {
            let existing = try loadBundle(
                from: finalDirectory,
                expectedCaptureID: captureID
            )
            guard existing.upload == upload else {
                throw RecognitionStudyPendingCaptureUploadStoreError
                    .captureConflict(captureID)
            }
            return existing.upload
        }

        let existingCount = try pendingBundles().count
        try requireLimit(
            UInt64(existingCount + 1),
            maximum: UInt64(quotas.maximumPendingCount),
            field: "pendingCount"
        )

        let requestData = upload.canonicalRequestBody
        let envelopeData = try upload.envelope.canonicalData()
        let packetData = try upload.packet.canonicalData()
        let commit = try RecognitionStudyPendingCaptureUploadCommit(
            captureAuthorizationID: upload.captureAuthorizationID,
            enqueuedAtUnixMilliseconds: enqueuedAtUnixMilliseconds,
            requestData: requestData,
            envelopeData: envelopeData,
            packetData: packetData
        )
        let commitData = try commit.canonicalData()
        let addedBytes = [
            requestData.count,
            envelopeData.count,
            packetData.count,
            commitData.count
        ].reduce(UInt64(0)) { $0 + UInt64($1) }
        try requireStoreCapacity(adding: addedBytes)

        let stagedDirectory = stagingURL(captureID)
        if fileManager.fileExists(atPath: stagedDirectory.path) {
            try quarantine(
                stagedDirectory,
                reason: "superseded-stage"
            )
        }
        try createProtectedDirectory(stagedDirectory)
        // Persist the immutable intent first. Recovery still requires all
        // three bound payloads before promotion, but a crash after those files
        // reach stable storage no longer strands a complete upload.
        try writeProtected(
            commitData,
            to: stagedDirectory.appendingPathComponent(Self.commitFileName)
        )
        try writeProtected(
            requestData,
            to: stagedDirectory.appendingPathComponent(Self.requestFileName)
        )
        try writeProtected(
            envelopeData,
            to: stagedDirectory.appendingPathComponent(Self.envelopeFileName)
        )
        try writeProtected(
            packetData,
            to: stagedDirectory.appendingPathComponent(Self.packetFileName)
        )
        try hooks.injectFault(.afterPayloadSynchronizationBeforePromotion)
        _ = try loadBundle(
            from: stagedDirectory,
            expectedCaptureID: captureID
        )
        try synchronizeDirectoryIfSupported(stagedDirectory)
        try hooks.injectFault(.afterCommitSynchronizationBeforePromotion)
        try performIO {
            try fileManager.moveItem(
                at: stagedDirectory,
                to: finalDirectory
            )
        }
        try synchronizeDirectoryIfSupported(pendingDirectory)
        try synchronizeDirectoryIfSupported(stagingDirectory)
        return upload
    }

    func pendingUploads() throws -> [RecognitionStudyPreparedCaptureUpload] {
        try refreshBeforeOperation()
        try requireUploadsPermittedWithoutRefresh()
        try enforceExistingQuotas()
        return try pendingBundles()
            .sorted {
                let lhsSession = $0.upload.envelope.serviceSessionID.rawValue
                let rhsSession = $1.upload.envelope.serviceSessionID.rawValue
                if lhsSession != rhsSession {
                    return lhsSession < rhsSession
                }
                if $0.upload.envelope.ticketOrdinal
                    != $1.upload.envelope.ticketOrdinal {
                    return $0.upload.envelope.ticketOrdinal
                        < $1.upload.envelope.ticketOrdinal
                }
                return $0.upload.captureAuthorizationID.rawValue
                    < $1.upload.captureAuthorizationID.rawValue
            }
            .map(\.upload)
    }

    func removeAcknowledged(
        by receipt: RecognitionStudyCaptureReceipt
    ) throws {
        try refreshBeforeOperation()
        let captureID = receipt.captureAuthorizationID.rawValue
        let finalDirectory = pendingURL(captureID)
        guard fileManager.fileExists(atPath: finalDirectory.path) else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .captureNotFound(captureID)
        }
        let bundle = try loadBundle(
            from: finalDirectory,
            expectedCaptureID: captureID
        )
        try receipt.validateBinding(
            envelope: bundle.upload.envelope,
            packet: bundle.upload.packet
        )

        let acknowledged = acknowledgedURL(captureID)
        if fileManager.fileExists(atPath: acknowledged.path) {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("acknowledged identity collision")
        }
        try performIO {
            try fileManager.moveItem(at: finalDirectory, to: acknowledged)
        }
        try synchronizeDirectoryIfSupported(pendingDirectory)
        try synchronizeDirectoryIfSupported(acknowledgedDirectory)
        try hooks.injectFault(.afterAcknowledgedMoveBeforeRemoval)
        try performIO {
            try fileManager.removeItem(at: acknowledged)
        }
        try synchronizeDirectoryIfSupported(acknowledgedDirectory)
    }

    /// Installs a durable local upload barrier before deleting all locally
    /// queued raw captures. The intent contains no credential or handwriting.
    /// Once installed, it remains active after server acknowledgement; only a
    /// separately reviewed future re-consent flow may clear that boundary.
    func registerWithdrawalBarrierAndPurge(
        consentRecordID: UUID,
        clientRequestID: UUID
    ) throws -> RecognitionStudyPendingConsentWithdrawal {
        try refreshBeforeOperation()
        let requested = try RecognitionStudyPendingConsentWithdrawal(
            clientRequestID: clientRequestID,
            consentRecordID: consentRecordID
        )
        let state: RecognitionStudyConsentWithdrawalBarrierState
        do {
            state = try withdrawalBarrierStateWithoutRefresh()
        } catch {
            // A corrupt marker is still a fail-closed marker. Delete any raw
            // queue bytes before surfacing the corruption for repair.
            try purgeRawUploadDataWithoutRefresh()
            throw error
        }
        switch state {
        case .none:
            let data = try requested.canonicalData()
            try writeProtected(
                data,
                to: withdrawalDirectory.appendingPathComponent(
                    Self.withdrawalIntentFileName
                )
            )
        case .pending(let existing), .acknowledged(let existing, _):
            guard existing == requested else {
                throw RecognitionStudyPendingCaptureUploadStoreError
                    .withdrawalIntentConflict
            }
        }
        // The barrier is durable before any raw bytes are removed. If deletion
        // fails, future enqueue/flush attempts remain blocked and a retry can
        // resume the purge without changing the idempotency key.
        try purgeRawUploadDataWithoutRefresh()
        return requested
    }

    func withdrawalBarrierState()
        throws -> RecognitionStudyConsentWithdrawalBarrierState
    {
        try refreshBeforeOperation()
        return try withdrawalBarrierStateWithoutRefresh()
    }

    func requireUploadsPermitted() throws {
        try refreshBeforeOperation()
        try requireUploadsPermittedWithoutRefresh()
    }

    func markWithdrawalAcknowledged(
        _ response: RecognitionStudyConsentResponse,
        for intent: RecognitionStudyPendingConsentWithdrawal
    ) throws {
        try refreshBeforeOperation()
        guard response.status == .withdrawn,
              response.consent?.consentRecordID == intent.consentRecordID else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("withdrawal acknowledgement binding")
        }
        let state = try withdrawalBarrierStateWithoutRefresh()
        switch state {
        case .none:
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("missing withdrawal intent")
        case .pending(let existing):
            guard existing == intent else {
                throw RecognitionStudyPendingCaptureUploadStoreError
                    .withdrawalIntentConflict
            }
            let data = try response.canonicalData()
            try writeProtected(
                data,
                to: withdrawalDirectory.appendingPathComponent(
                    Self.withdrawalAcknowledgementFileName
                )
            )
        case .acknowledged(let existing, let acknowledged):
            guard existing == intent, acknowledged == response else {
                throw RecognitionStudyPendingCaptureUploadStoreError
                    .withdrawalIntentConflict
            }
        }
    }

    /// Intended for a separately reviewed withdrawal/account-deletion flow.
    /// It is not called by the current offline Study UI.
    func purgeAllPendingAndQuarantinedData() throws {
        try refreshBeforeOperation()
        try purgeRawUploadDataWithoutRefresh()
    }

    private func purgeRawUploadDataWithoutRefresh() throws {
        for directory in [
            pendingDirectory,
            stagingDirectory,
            acknowledgedDirectory,
            quarantineDirectory
        ] {
            for item in try childItems(of: directory) {
                try performIO { try fileManager.removeItem(at: item) }
            }
            try synchronizeDirectoryIfSupported(directory)
        }
    }

    private func start() throws {
        guard !hasStarted else { return }
        try requireProtectedData()
        try bootstrapDirectories()
        try recoverAcknowledged()
        try recoverStaging()
        hasStarted = true
    }
}

private struct RecognitionStudyPendingCaptureUploadCommit:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let currentSchemaVersion =
        "recognition-study-pending-capture-upload-commit-v1"
    static let maximumCanonicalJSONByteCount = 4 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let captureAuthorizationID: RecognitionStudyCanonicalUUID
    let enqueuedAtUnixMilliseconds: Int64
    let requestSHA256: RecognitionStudySHA256
    let requestByteCount: UInt64
    let envelopeSHA256: RecognitionStudySHA256
    let envelopeByteCount: UInt64
    let packetSHA256: RecognitionStudySHA256
    let packetByteCount: UInt64

    init(
        captureAuthorizationID: RecognitionStudyCanonicalUUID,
        enqueuedAtUnixMilliseconds: Int64,
        requestData: Data,
        envelopeData: Data,
        packetData: Data
    ) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        self.captureAuthorizationID = captureAuthorizationID
        self.enqueuedAtUnixMilliseconds = enqueuedAtUnixMilliseconds
        requestSHA256 = RecognitionStudySHA256(digesting: requestData)
        requestByteCount = UInt64(requestData.count)
        envelopeSHA256 = RecognitionStudySHA256(digesting: envelopeData)
        envelopeByteCount = UInt64(envelopeData.count)
        packetSHA256 = RecognitionStudySHA256(digesting: packetData)
        packetByteCount = UInt64(packetData.count)
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: Wire.self,
            construct: { try Self(wire: $0) }
        )
    }

    private init(wire: Wire) throws {
        schemaVersion = wire.schemaVersion
        captureAuthorizationID = wire.captureAuthorizationID
        enqueuedAtUnixMilliseconds = wire.enqueuedAtUnixMilliseconds
        requestSHA256 = wire.requestSHA256
        requestByteCount = wire.requestByteCount
        envelopeSHA256 = wire.envelopeSHA256
        envelopeByteCount = wire.envelopeByteCount
        packetSHA256 = wire.packetSHA256
        packetByteCount = wire.packetByteCount
        try validateContract()
    }

    func validateContract() throws {
        guard schemaVersion.rawValue == Self.currentSchemaVersion else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("commit schema")
        }
        let maximumSafeInteger: UInt64 = 9_007_199_254_740_991
        guard enqueuedAtUnixMilliseconds >= 0,
              UInt64(enqueuedAtUnixMilliseconds) <= maximumSafeInteger,
              requestByteCount > 0,
              requestByteCount <= UInt64(
                  RecognitionStudyCaptureUploadRequest
                    .maximumCanonicalJSONByteCount
              ),
              envelopeByteCount > 0,
              envelopeByteCount <= UInt64(
                  RecognitionStudyAuthorizedCaptureEnvelope
                    .maximumCanonicalJSONByteCount
              ),
              packetByteCount > 0,
              packetByteCount <= UInt64(
                  RecognitionStudyCaptureLimits.maximumCanonicalPacketByteCount
              ) else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("commit limits")
        }
    }

    private struct Wire: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let captureAuthorizationID: RecognitionStudyCanonicalUUID
        let enqueuedAtUnixMilliseconds: Int64
        let requestSHA256: RecognitionStudySHA256
        let requestByteCount: UInt64
        let envelopeSHA256: RecognitionStudySHA256
        let envelopeByteCount: UInt64
        let packetSHA256: RecognitionStudySHA256
        let packetByteCount: UInt64
    }
}

private struct RecognitionStudyPendingCaptureUploadBundle {
    let directory: URL
    let upload: RecognitionStudyPreparedCaptureUpload
    let commit: RecognitionStudyPendingCaptureUploadCommit
}

private extension RecognitionStudyPendingCaptureUploadStore {
    func refreshBeforeOperation() throws {
        if !hasStarted {
            try start()
            return
        }
        try requireProtectedData()
        try recoverAcknowledged()
        try recoverStaging()
    }

    func bootstrapDirectories() throws {
        try createProtectedDirectory(storeDirectory)
        try createProtectedDirectory(pendingDirectory)
        try createProtectedDirectory(stagingDirectory)
        try createProtectedDirectory(acknowledgedDirectory)
        try createProtectedDirectory(quarantineDirectory)
        try createProtectedDirectory(withdrawalDirectory)
    }

    func requireUploadsPermittedWithoutRefresh() throws {
        guard case .none = try withdrawalBarrierStateWithoutRefresh() else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .withdrawalBarrierActive
        }
    }

    func withdrawalBarrierStateWithoutRefresh()
        throws -> RecognitionStudyConsentWithdrawalBarrierState
    {
        let names = try performIO {
            try Set(
                fileManager.contentsOfDirectory(
                    atPath: withdrawalDirectory.path
                )
            )
        }
        let intentName = Self.withdrawalIntentFileName
        let acknowledgementName = Self.withdrawalAcknowledgementFileName
        guard names.isEmpty
                || names == Set([intentName])
                || names == Set([intentName, acknowledgementName]) else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("withdrawal bundle contents")
        }
        guard names.contains(intentName) else { return .none }

        let intent = try RecognitionStudyPendingConsentWithdrawal
            .decodeCanonicalData(
                readCappedData(
                    at: withdrawalDirectory.appendingPathComponent(intentName),
                    maximumByteCount: RecognitionStudyPendingConsentWithdrawal
                        .maximumCanonicalJSONByteCount,
                    artifactName: intentName
                )
            )
        guard names.contains(acknowledgementName) else {
            return .pending(intent)
        }
        let response = try RecognitionStudyConsentResponse.decodeCanonicalData(
            readCappedData(
                at: withdrawalDirectory.appendingPathComponent(
                    acknowledgementName
                ),
                maximumByteCount: RecognitionStudyConsentResponse
                    .maximumCanonicalJSONByteCount,
                artifactName: acknowledgementName
            )
        )
        guard response.status == .withdrawn,
              response.consent?.consentRecordID == intent.consentRecordID else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("withdrawal acknowledgement binding")
        }
        return .acknowledged(intent, response)
    }

    func recoverAcknowledged() throws {
        for item in try childItems(of: acknowledgedDirectory) {
            try performIO { try fileManager.removeItem(at: item) }
        }
        try synchronizeDirectoryIfSupported(acknowledgedDirectory)
    }

    func recoverStaging() throws {
        for stage in try childItems(of: stagingDirectory) {
            let captureID = stage.lastPathComponent
            guard try isDirectory(stage), isCanonicalUUID(captureID) else {
                try quarantine(stage, reason: "invalid-stage")
                continue
            }
            let commitURL = stage.appendingPathComponent(Self.commitFileName)
            guard fileManager.fileExists(atPath: commitURL.path) else {
                try quarantine(stage, reason: "incomplete-stage")
                continue
            }
            do {
                let staged = try loadBundle(
                    from: stage,
                    expectedCaptureID: captureID
                )
                let final = pendingURL(captureID)
                if fileManager.fileExists(atPath: final.path) {
                    let existing = try loadBundle(
                        from: final,
                        expectedCaptureID: captureID
                    )
                    if existing.upload == staged.upload,
                       existing.commit == staged.commit {
                        try performIO { try fileManager.removeItem(at: stage) }
                    } else {
                        try quarantine(stage, reason: "conflicting-stage")
                    }
                } else {
                    try performIO {
                        try fileManager.moveItem(at: stage, to: final)
                    }
                    try synchronizeDirectoryIfSupported(pendingDirectory)
                }
                try synchronizeDirectoryIfSupported(stagingDirectory)
            } catch {
                if isProtectedDataError(error) { throw error }
                try quarantine(stage, reason: "corrupt-stage")
            }
        }
    }

    func pendingBundles() throws -> [RecognitionStudyPendingCaptureUploadBundle] {
        var bundles: [RecognitionStudyPendingCaptureUploadBundle] = []
        for directory in try childItems(of: pendingDirectory) {
            let captureID = directory.lastPathComponent
            guard try isDirectory(directory), isCanonicalUUID(captureID) else {
                throw RecognitionStudyPendingCaptureUploadStoreError
                    .corruptArtifact("invalid pending item")
            }
            bundles.append(
                try loadBundle(
                    from: directory,
                    expectedCaptureID: captureID
                )
            )
        }
        return bundles
    }

    func loadBundle(
        from directory: URL,
        expectedCaptureID: String
    ) throws -> RecognitionStudyPendingCaptureUploadBundle {
        try requireExactItemNames(
            in: directory,
            expected: [
                Self.requestFileName,
                Self.envelopeFileName,
                Self.packetFileName,
                Self.commitFileName
            ]
        )
        let requestData = try readCappedData(
            at: directory.appendingPathComponent(Self.requestFileName),
            maximumByteCount:
                RecognitionStudyCaptureUploadRequest
                    .maximumCanonicalJSONByteCount,
            artifactName: Self.requestFileName
        )
        let envelopeData = try readCappedData(
            at: directory.appendingPathComponent(Self.envelopeFileName),
            maximumByteCount:
                RecognitionStudyAuthorizedCaptureEnvelope
                    .maximumCanonicalJSONByteCount,
            artifactName: Self.envelopeFileName
        )
        let packetData = try readCappedData(
            at: directory.appendingPathComponent(Self.packetFileName),
            maximumByteCount:
                RecognitionStudyCaptureLimits.maximumCanonicalPacketByteCount,
            artifactName: Self.packetFileName
        )
        let commitData = try readCappedData(
            at: directory.appendingPathComponent(Self.commitFileName),
            maximumByteCount:
                RecognitionStudyPendingCaptureUploadCommit
                    .maximumCanonicalJSONByteCount,
            artifactName: Self.commitFileName
        )
        let commit = try RecognitionStudyPendingCaptureUploadCommit
            .decodeCanonicalData(commitData)
        guard commit.captureAuthorizationID.rawValue == expectedCaptureID,
              commit.requestByteCount == UInt64(requestData.count),
              commit.requestSHA256
                == RecognitionStudySHA256(digesting: requestData),
              commit.envelopeByteCount == UInt64(envelopeData.count),
              commit.envelopeSHA256
                == RecognitionStudySHA256(digesting: envelopeData),
              commit.packetByteCount == UInt64(packetData.count),
              commit.packetSHA256
                == RecognitionStudySHA256(digesting: packetData) else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("commit binding")
        }
        let upload: RecognitionStudyPreparedCaptureUpload
        do {
            upload = try RecognitionStudyPreparedCaptureUpload(
                restoringCanonicalRequestBody: requestData,
                canonicalEnvelopeData: envelopeData,
                canonicalPacketData: packetData
            )
        } catch {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("prepared upload binding")
        }
        guard upload.captureAuthorizationID.rawValue == expectedCaptureID else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("capture identity")
        }
        return RecognitionStudyPendingCaptureUploadBundle(
            directory: directory,
            upload: upload,
            commit: commit
        )
    }

    func enforceExistingQuotas() throws {
        let count = try pendingBundles().count
        try requireLimit(
            UInt64(count),
            maximum: UInt64(quotas.maximumPendingCount),
            field: "pendingCount"
        )
        try requireLimit(
            try storeByteCount(),
            maximum: quotas.maximumStoreByteCount,
            field: "storeByteCount"
        )
    }

    func requireStoreCapacity(adding byteCount: UInt64) throws {
        let existing = try storeByteCount()
        let (total, overflow) = existing.addingReportingOverflow(byteCount)
        guard !overflow else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .quotaExceeded(
                    field: "storeByteCount",
                    maximum: quotas.maximumStoreByteCount,
                    actual: UInt64.max
                )
        }
        try requireLimit(
            total,
            maximum: quotas.maximumStoreByteCount,
            field: "storeByteCount"
        )
    }

    func requireLimit(
        _ actual: UInt64,
        maximum: UInt64,
        field: String
    ) throws {
        guard actual <= maximum else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .quotaExceeded(
                    field: field,
                    maximum: maximum,
                    actual: actual
                )
        }
    }

    func storeByteCount() throws -> UInt64 {
        var total: UInt64 = 0
        let enumerator = fileManager.enumerator(
            at: storeDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: []
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try performIO {
                try url.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey
                    ]
                )
            }
            guard values.isSymbolicLink != true else {
                throw RecognitionStudyPendingCaptureUploadStoreError
                    .corruptArtifact("symbolic link")
            }
            if values.isRegularFile == true {
                let size = UInt64(values.fileSize ?? 0)
                let (next, overflow) = total.addingReportingOverflow(size)
                guard !overflow else {
                    throw RecognitionStudyPendingCaptureUploadStoreError
                        .corruptArtifact("store byte count overflow")
                }
                total = next
            }
        }
        return total
    }

    func createProtectedDirectory(_ url: URL) throws {
        try requireProtectedData()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue, try !isSymbolicLink(url) else {
                throw RecognitionStudyPendingCaptureUploadStoreError
                    .corruptArtifact("expected directory")
            }
        } else {
            try performIO {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: [
                        .protectionKey: FileProtectionType.complete
                    ]
                )
            }
        }
        try applyStoragePolicy(to: url)
    }

    func writeProtected(_ data: Data, to url: URL) throws {
        try requireProtectedData()
        guard !fileManager.fileExists(atPath: url.path) else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("refusing overwrite")
        }
        try performIO {
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtection]
            )
        }
        try applyStoragePolicy(to: url)
        try synchronizeFile(url)
        try synchronizeDirectoryIfSupported(url.deletingLastPathComponent())
    }

    func applyStoragePolicy(to url: URL) throws {
        hooks.observePolicyRequest(.completeFileProtection(url))
        try performIO {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        }
        hooks.observePolicyRequest(.excludeFromBackup(url))
        try performIO {
            var mutableURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutableURL.setResourceValues(values)
        }
    }

    func synchronizeFile(_ url: URL) throws {
        hooks.observePolicyRequest(.synchronize(url))
        try performIO {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.synchronize()
        }
    }

    func synchronizeDirectoryIfSupported(_ url: URL) throws {
        hooks.observePolicyRequest(.synchronize(url))
        for attempt in 0..<3 {
            do {
                try performIO {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    try handle.synchronize()
                }
                return
            } catch {
                if isProtectedDataError(error) {
                    throw RecognitionStudyPendingCaptureUploadStoreError
                        .protectedDataUnavailable
                }
                let nsError = error as NSError
                let underlying = nsError.userInfo[NSUnderlyingErrorKey]
                    as? NSError
                let posixCode: Int? = {
                    if nsError.domain == NSPOSIXErrorDomain {
                        return nsError.code
                    }
                    if underlying?.domain == NSPOSIXErrorDomain {
                        return underlying?.code
                    }
                    return nil
                }()
                // Simulator/APFS directory fsync can report EAGAIN even after
                // every payload file has synchronized. Reopen and retry before
                // treating directory fsync as unsupported on that filesystem.
                if posixCode == 35, attempt < 2 {
                    continue
                }
                if let posixCode, [9, 21, 22, 35].contains(posixCode) {
                    return
                }
                var isDirectory: ObjCBool = false
                let directoryStillExists = fileManager.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                ) && isDirectory.boolValue
                if nsError.domain == NSCocoaErrorDomain,
                   directoryStillExists,
                   [
                        CocoaError.Code.fileNoSuchFile.rawValue,
                        CocoaError.Code.fileWriteUnknown.rawValue
                   ].contains(nsError.code),
                   let underlying,
                   underlying.domain == NSPOSIXErrorDomain,
                   [0, 2, 9, 21, 22].contains(underlying.code) {
                    return
                }
                throw error
            }
        }
    }

    func readCappedData(
        at url: URL,
        maximumByteCount: Int,
        artifactName: String
    ) throws -> Data {
        guard try isRegularFile(url), try !isSymbolicLink(url) else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("invalid \(artifactName)")
        }
        let size = try performIO {
            try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }
        guard size <= maximumByteCount else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("oversized \(artifactName)")
        }
        let data = try performIO { try Data(contentsOf: url) }
        guard data.count == size, data.count <= maximumByteCount else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("changed \(artifactName)")
        }
        return data
    }

    func requireExactItemNames(
        in directory: URL,
        expected: Set<String>
    ) throws {
        let names = try performIO {
            try Set(fileManager.contentsOfDirectory(atPath: directory.path))
        }
        guard names == expected else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .corruptArtifact("unexpected bundle contents")
        }
    }

    func childItems(of directory: URL) throws -> [URL] {
        try performIO {
            try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: []
            )
        }
    }

    func isDirectory(_ url: URL) throws -> Bool {
        try performIO {
            try url.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory == true
        }
    }

    func isRegularFile(_ url: URL) throws -> Bool {
        try performIO {
            try url.resourceValues(
                forKeys: [.isRegularFileKey]
            ).isRegularFile == true
        }
    }

    func isSymbolicLink(_ url: URL) throws -> Bool {
        try performIO {
            try url.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink == true
        }
    }

    func quarantine(_ item: URL, reason: String) throws {
        let destination = quarantineDirectory.appendingPathComponent(
            "\(reason)-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try performIO { try fileManager.moveItem(at: item, to: destination) }
        try applyStoragePolicy(to: destination)
        try synchronizeDirectoryIfSupported(quarantineDirectory)
        try synchronizeDirectoryIfSupported(item.deletingLastPathComponent())
    }

    func pendingURL(_ captureID: String) -> URL {
        pendingDirectory.appendingPathComponent(captureID, isDirectory: true)
    }

    func stagingURL(_ captureID: String) -> URL {
        stagingDirectory.appendingPathComponent(captureID, isDirectory: true)
    }

    func acknowledgedURL(_ captureID: String) -> URL {
        acknowledgedDirectory.appendingPathComponent(
            captureID,
            isDirectory: true
        )
    }

    func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    func requireProtectedData() throws {
        guard hooks.isProtectedDataAvailable() else {
            throw RecognitionStudyPendingCaptureUploadStoreError
                .protectedDataUnavailable
        }
    }

    func performIO<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch {
            if hooks.classifiesProtectedDataError(error) {
                throw RecognitionStudyPendingCaptureUploadStoreError
                    .protectedDataUnavailable
            }
            throw error
        }
    }

    func isProtectedDataError(_ error: Error) -> Bool {
        if let storeError = error
                as? RecognitionStudyPendingCaptureUploadStoreError,
           storeError == .protectedDataUnavailable {
            return true
        }
        return hooks.classifiesProtectedDataError(error)
    }
}
