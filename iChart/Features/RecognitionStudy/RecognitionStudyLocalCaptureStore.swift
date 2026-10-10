import CryptoKit
import Foundation

enum RecognitionStudyLocalCaptureStoreError: Error, Equatable {
    case protectedDataUnavailable
    case sessionNotFound(String)
    case sessionDeleted(String)
    case sessionConflict(String)
    case authorizationConflict(String)
    case captureIDConflict(String)
    case captureOrdinalConflict(UInt32)
    case quotaExceeded(field: String, maximum: UInt64, actual: UInt64)
    case artifactTooLarge(name: String, maximum: UInt64, actual: UInt64)
    case corruptArtifact(String)
    case invalidQuotaConfiguration(String)
}

enum RecognitionStudyLocalCaptureStoreFaultPoint: String, Sendable {
    case afterStagedPayloadVerificationBeforeCommitMarker
    case afterCommitMarkerSynchronizationBeforePromotion
    case afterDeletionTombstoneSynchronizationBeforeRemoval
}

enum RecognitionStudyLocalCaptureStorePolicyRequest: Equatable, Sendable {
    case completeFileProtection(URL)
    case excludeFromBackup(URL)
    case synchronize(URL)
}

struct RecognitionStudyLocalCaptureStoreHooks: Sendable {
    var isProtectedDataAvailable: @Sendable () -> Bool
    var classifiesProtectedDataError: @Sendable (Error) -> Bool
    var observePolicyRequest:
        @Sendable (RecognitionStudyLocalCaptureStorePolicyRequest) -> Void
    var injectFault:
        @Sendable (RecognitionStudyLocalCaptureStoreFaultPoint) throws -> Void

    init(
        isProtectedDataAvailable: @escaping @Sendable () -> Bool = { true },
        classifiesProtectedDataError:
            @escaping @Sendable (Error) -> Bool = { error in
                let nsError = error as NSError
                guard nsError.domain == NSCocoaErrorDomain else {
                    return false
                }
                return nsError.code == CocoaError.Code.fileReadNoPermission.rawValue
                    || nsError.code
                        == CocoaError.Code.fileWriteNoPermission.rawValue
            },
        observePolicyRequest:
            @escaping @Sendable (
                RecognitionStudyLocalCaptureStorePolicyRequest
            ) -> Void = { _ in },
        injectFault:
            @escaping @Sendable (
                RecognitionStudyLocalCaptureStoreFaultPoint
            ) throws -> Void = { _ in }
    ) {
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.classifiesProtectedDataError = classifiesProtectedDataError
        self.observePolicyRequest = observePolicyRequest
        self.injectFault = injectFault
    }
}

struct RecognitionStudyLocalCaptureStoreQuotas: Equatable, Sendable {
    let maximumCapturesPerSession: UInt32
    let maximumSessionByteCount: UInt64
    let maximumStoreByteCount: UInt64
    let maximumSessionCount: UInt32

    static let contract = Self(
        uncheckedMaximumCapturesPerSession:
            RecognitionStudyCaptureLimits.maximumCapturesPerSession,
        maximumSessionByteCount:
            RecognitionStudyCaptureLimits.maximumSessionByteCount,
        maximumStoreByteCount:
            RecognitionStudyCaptureLimits.maximumStoreByteCount,
        maximumSessionCount:
            RecognitionStudyCaptureLimits.maximumSessionCount
    )

    init(
        maximumCapturesPerSession: UInt32,
        maximumSessionByteCount: UInt64,
        maximumStoreByteCount: UInt64,
        maximumSessionCount: UInt32
    ) throws {
        guard maximumCapturesPerSession > 0,
              maximumCapturesPerSession
                <= RecognitionStudyCaptureLimits.maximumCapturesPerSession else {
            throw RecognitionStudyLocalCaptureStoreError
                .invalidQuotaConfiguration("maximumCapturesPerSession")
        }
        guard maximumSessionByteCount > 0,
              maximumSessionByteCount
                <= RecognitionStudyCaptureLimits.maximumSessionByteCount else {
            throw RecognitionStudyLocalCaptureStoreError
                .invalidQuotaConfiguration("maximumSessionByteCount")
        }
        guard maximumStoreByteCount > 0,
              maximumStoreByteCount
                <= RecognitionStudyCaptureLimits.maximumStoreByteCount else {
            throw RecognitionStudyLocalCaptureStoreError
                .invalidQuotaConfiguration("maximumStoreByteCount")
        }
        guard maximumSessionCount > 0,
              maximumSessionCount
                <= RecognitionStudyCaptureLimits.maximumSessionCount else {
            throw RecognitionStudyLocalCaptureStoreError
                .invalidQuotaConfiguration("maximumSessionCount")
        }
        self.maximumCapturesPerSession = maximumCapturesPerSession
        self.maximumSessionByteCount = maximumSessionByteCount
        self.maximumStoreByteCount = maximumStoreByteCount
        self.maximumSessionCount = maximumSessionCount
    }

    private init(
        uncheckedMaximumCapturesPerSession: UInt32,
        maximumSessionByteCount: UInt64,
        maximumStoreByteCount: UInt64,
        maximumSessionCount: UInt32
    ) {
        maximumCapturesPerSession = uncheckedMaximumCapturesPerSession
        self.maximumSessionByteCount = maximumSessionByteCount
        self.maximumStoreByteCount = maximumStoreByteCount
        self.maximumSessionCount = maximumSessionCount
    }
}

struct RecognitionStudyStoredCapture: Hashable, Sendable {
    let packet: ChordInkCanonicalTrajectoryPacket
    let envelope: RecognitionStudyCaptureEnvelope
}

/// A local-only engineering store. Deletion removes the store's logical
/// references and files but is not a claim of forensic erasure from flash,
/// snapshots, backups made before exclusion, or operating-system caches.
actor RecognitionStudyLocalCaptureStore {
    static let storeDirectoryName = "recognition-study-store-v1"

    private static let sessionsDirectoryName = "sessions"
    private static let tombstonesDirectoryName = "deletion-tombstones"
    private static let quarantineDirectoryName = "quarantine"
    private static let sessionFileName = "session.json"
    private static let capturesDirectoryName = "captures"
    private static let stagingDirectoryName = "staging"
    private static let sessionQuarantineDirectoryName = "quarantine"
    private static let trajectoryFileName = "trajectory.json"
    private static let envelopeFileName = "envelope.json"
    private static let commitFileName = "commit.json"

    private let fileManager = FileManager()
    private let hooks: RecognitionStudyLocalCaptureStoreHooks
    private let quotas: RecognitionStudyLocalCaptureStoreQuotas
    private let storeDirectory: URL
    private let sessionsDirectory: URL
    private let tombstonesDirectory: URL
    private let quarantineDirectory: URL
    private var hasStarted = false

    private init(
        rootDirectory: URL,
        hooks: RecognitionStudyLocalCaptureStoreHooks,
        quotas: RecognitionStudyLocalCaptureStoreQuotas
    ) {
        self.hooks = hooks
        self.quotas = quotas
        storeDirectory = rootDirectory.appendingPathComponent(
            Self.storeDirectoryName,
            isDirectory: true
        )
        sessionsDirectory = storeDirectory.appendingPathComponent(
            Self.sessionsDirectoryName,
            isDirectory: true
        )
        tombstonesDirectory = storeDirectory.appendingPathComponent(
            Self.tombstonesDirectoryName,
            isDirectory: true
        )
        quarantineDirectory = storeDirectory.appendingPathComponent(
            Self.quarantineDirectoryName,
            isDirectory: true
        )
    }

    static func open(
        rootDirectory: URL,
        hooks: RecognitionStudyLocalCaptureStoreHooks = .init(),
        quotas: RecognitionStudyLocalCaptureStoreQuotas = .contract
    ) async throws -> RecognitionStudyLocalCaptureStore {
        let store = RecognitionStudyLocalCaptureStore(
            rootDirectory: rootDirectory,
            hooks: hooks,
            quotas: quotas
        )
        try await store.recover()
        return store
    }

    func recover() throws {
        try requireProtectedData()
        try bootstrapDirectories()
        try recoverDeletionTombstones()
        try recoverSessions()
        hasStarted = true
    }

    @discardableResult
    func createSession(
        _ manifest: RecognitionStudySessionManifest
    ) throws -> RecognitionStudySessionManifest {
        try refreshBeforeOperation()
        let sessionID = manifest.localSessionID.rawValue
        guard !fileManager.fileExists(atPath: tombstoneURL(sessionID).path) else {
            throw RecognitionStudyLocalCaptureStoreError.sessionDeleted(sessionID)
        }

        let manifestData = try manifest.canonicalData()
        let finalDirectory = sessionDirectory(sessionID)
        if fileManager.fileExists(atPath: finalDirectory.path) {
            let existing = try loadSessionManifest(from: finalDirectory)
            guard existing == manifest else {
                throw RecognitionStudyLocalCaptureStoreError
                    .sessionConflict(sessionID)
            }
            return existing
        }

        let activeSessionCount = try validSessionManifests().count
        try requireLimit(
            UInt64(activeSessionCount + 1),
            maximum: UInt64(quotas.maximumSessionCount),
            field: "sessionCount"
        )
        try requireLimit(
            UInt64(manifestData.count),
            maximum: quotas.maximumSessionByteCount,
            field: "sessionByteCount"
        )
        try requireStoreCapacity(adding: UInt64(manifestData.count))

        let temporaryDirectory = sessionsDirectory.appendingPathComponent(
            ".session-\(sessionID)-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try createProtectedDirectory(temporaryDirectory)
        try writeProtected(
            manifestData,
            to: temporaryDirectory.appendingPathComponent(Self.sessionFileName)
        )
        try createProtectedDirectory(
            temporaryDirectory.appendingPathComponent(
                Self.capturesDirectoryName,
                isDirectory: true
            )
        )
        try createProtectedDirectory(
            temporaryDirectory.appendingPathComponent(
                Self.stagingDirectoryName,
                isDirectory: true
            )
        )
        try createProtectedDirectory(
            temporaryDirectory.appendingPathComponent(
                Self.sessionQuarantineDirectoryName,
                isDirectory: true
            )
        )
        _ = try loadSessionManifest(from: temporaryDirectory)
        try synchronizeDirectoryIfSupported(temporaryDirectory)
        try performIO {
            try fileManager.moveItem(
                at: temporaryDirectory,
                to: finalDirectory
            )
        }
        try synchronizeDirectoryIfSupported(sessionsDirectory)
        return manifest
    }

    func sessionManifest(
        localSessionID: UUID
    ) throws -> RecognitionStudySessionManifest? {
        try refreshBeforeOperation()
        let sessionID = RecognitionStudyCanonicalUUID(localSessionID).rawValue
        guard !fileManager.fileExists(atPath: tombstoneURL(sessionID).path) else {
            return nil
        }
        let directory = sessionDirectory(sessionID)
        guard fileManager.fileExists(atPath: directory.path) else {
            return nil
        }
        return try loadSessionManifest(from: directory)
    }

    func storeCapture(
        localSessionID: UUID,
        authorizationID: UUID,
        localCaptureID: UUID,
        captureOrdinal: UInt32,
        clientCapturedAtUnixMilliseconds: Int64,
        presentedSurface: RecognitionStudyPresentedSurface,
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws -> RecognitionStudyStoredCapture {
        try refreshBeforeOperation()
        let sessionID = RecognitionStudyCanonicalUUID(localSessionID).rawValue
        guard !fileManager.fileExists(atPath: tombstoneURL(sessionID).path) else {
            throw RecognitionStudyLocalCaptureStoreError.sessionDeleted(sessionID)
        }
        let sessionDirectory = sessionDirectory(sessionID)
        guard fileManager.fileExists(atPath: sessionDirectory.path) else {
            throw RecognitionStudyLocalCaptureStoreError.sessionNotFound(sessionID)
        }
        let session = try loadSessionManifest(from: sessionDirectory)

        let authorization = try RecognitionStudyAuthorizationBinding
            .localEngineeringDryRun(authorizationID: authorizationID)
        let descriptor = try RecognitionStudyTrajectoryDescriptor(
            derivingFrom: packet
        )
        let envelope = try RecognitionStudyCaptureEnvelope(
            localCaptureID: localCaptureID,
            captureOrdinal: captureOrdinal,
            authorizationBinding: authorization,
            sessionManifest: session,
            clientCapturedAtUnixMilliseconds:
                clientCapturedAtUnixMilliseconds,
            presentedSurface: presentedSurface,
            trajectoryDescriptor: descriptor
        )
        let packetData = try packet.canonicalData()
        try RecognitionStudyCaptureLimits
            .validateCanonicalPacketByteCountBeforeDecoding(packetData.count)
        let envelopeData = try envelope.canonicalData()

        let authorizationKey = authorization.authorizationID.rawValue
        if let existing = try committedBundle(
            authorizationKey: authorizationKey
        ) {
            guard existing.packetData == packetData,
                  existing.envelopeData == envelopeData else {
                throw RecognitionStudyLocalCaptureStoreError
                    .authorizationConflict(authorizationKey)
            }
            return RecognitionStudyStoredCapture(
                packet: existing.packet,
                envelope: existing.envelope
            )
        }
        try requireUniqueCaptureIdentity(for: envelope)

        let committedCount = try validCommittedBundles(
            in: sessionDirectory,
            manifest: session
        ).count
        try requireLimit(
            UInt64(committedCount + 1),
            maximum: UInt64(quotas.maximumCapturesPerSession),
            field: "capturesPerSession"
        )

        let provisionalCommit = try RecognitionStudyLocalCaptureCommitMarker(
            packetData: packetData,
            envelopeData: envelopeData,
            envelope: envelope
        )
        let commitData = try provisionalCommit.canonicalData()
        let addedBytes = UInt64(
            packetData.count + envelopeData.count + commitData.count
        )
        let currentSessionBytes = try directoryByteCount(sessionDirectory)
        try requireLimit(
            currentSessionBytes + addedBytes,
            maximum: quotas.maximumSessionByteCount,
            field: "sessionByteCount"
        )
        try requireStoreCapacity(adding: addedBytes)

        let stagingDirectory = sessionDirectory
            .appendingPathComponent(Self.stagingDirectoryName, isDirectory: true)
            .appendingPathComponent(authorizationKey, isDirectory: true)
        guard !fileManager.fileExists(atPath: stagingDirectory.path) else {
            throw RecognitionStudyLocalCaptureStoreError
                .authorizationConflict(authorizationKey)
        }
        try createProtectedDirectory(stagingDirectory)
        try writeProtected(
            packetData,
            to: stagingDirectory.appendingPathComponent(Self.trajectoryFileName)
        )
        try writeProtected(
            envelopeData,
            to: stagingDirectory.appendingPathComponent(Self.envelopeFileName)
        )

        let verifiedPayload = try loadStagedPayload(
            from: stagingDirectory,
            session: session,
            expectedAuthorizationKey: authorizationKey
        )
        guard verifiedPayload.packetData == packetData,
              verifiedPayload.envelopeData == envelopeData else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "staged payload differs from requested capture"
            )
        }
        try hooks.injectFault(
            .afterStagedPayloadVerificationBeforeCommitMarker
        )

        let verifiedCommit = try RecognitionStudyLocalCaptureCommitMarker(
            packetData: verifiedPayload.packetData,
            envelopeData: verifiedPayload.envelopeData,
            envelope: verifiedPayload.envelope
        )
        try writeProtected(
            try verifiedCommit.canonicalData(),
            to: stagingDirectory.appendingPathComponent(Self.commitFileName)
        )
        let completeBundle = try loadCommittedBundle(
            from: stagingDirectory,
            session: session,
            expectedAuthorizationKey: authorizationKey
        )
        try synchronizeDirectoryIfSupported(stagingDirectory)
        try hooks.injectFault(
            .afterCommitMarkerSynchronizationBeforePromotion
        )

        let finalDirectory = sessionDirectory
            .appendingPathComponent(Self.capturesDirectoryName, isDirectory: true)
            .appendingPathComponent(authorizationKey, isDirectory: true)
        guard !fileManager.fileExists(atPath: finalDirectory.path) else {
            throw RecognitionStudyLocalCaptureStoreError
                .authorizationConflict(authorizationKey)
        }
        try performIO {
            try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
        }
        try synchronizeDirectoryIfSupported(finalDirectory.deletingLastPathComponent())
        return RecognitionStudyStoredCapture(
            packet: completeBundle.packet,
            envelope: completeBundle.envelope
        )
    }

    func committedCaptures(
        localSessionID: UUID
    ) throws -> [RecognitionStudyStoredCapture] {
        try refreshBeforeOperation()
        let sessionID = RecognitionStudyCanonicalUUID(localSessionID).rawValue
        guard !fileManager.fileExists(atPath: tombstoneURL(sessionID).path) else {
            return []
        }
        let directory = sessionDirectory(sessionID)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw RecognitionStudyLocalCaptureStoreError.sessionNotFound(sessionID)
        }
        let manifest = try loadSessionManifest(from: directory)
        return try validCommittedBundles(in: directory, manifest: manifest)
            .sorted { lhs, rhs in
                if lhs.envelope.captureOrdinal != rhs.envelope.captureOrdinal {
                    return lhs.envelope.captureOrdinal
                        < rhs.envelope.captureOrdinal
                }
                return lhs.envelope.authorizationBinding.authorizationID.rawValue
                    < rhs.envelope.authorizationBinding.authorizationID.rawValue
            }
            .map {
                RecognitionStudyStoredCapture(
                    packet: $0.packet,
                    envelope: $0.envelope
                )
            }
    }

    func deleteSession(
        localSessionID: UUID,
        clientRequestedAtUnixMilliseconds: Int64
    ) throws {
        try refreshBeforeOperation()
        let sessionID = RecognitionStudyCanonicalUUID(localSessionID).rawValue
        let sessionDirectory = sessionDirectory(sessionID)
        let tombstoneURL = tombstoneURL(sessionID)

        if fileManager.fileExists(atPath: tombstoneURL.path) {
            _ = try loadDeletionTombstone(from: tombstoneURL)
            try completeDeletion(tombstoneURL: tombstoneURL)
            return
        }
        guard fileManager.fileExists(atPath: sessionDirectory.path) else {
            throw RecognitionStudyLocalCaptureStoreError.sessionNotFound(sessionID)
        }
        let manifest = try loadSessionManifest(from: sessionDirectory)
        let tombstone = try RecognitionStudySessionDeletionTombstone(
            manifest: manifest,
            clientRequestedAtUnixMilliseconds:
                clientRequestedAtUnixMilliseconds
        )
        try writeProtected(try tombstone.canonicalData(), to: tombstoneURL)
        try synchronizeDirectoryIfSupported(tombstonesDirectory)
        try hooks.injectFault(
            .afterDeletionTombstoneSynchronizationBeforeRemoval
        )
        try completeDeletion(tombstoneURL: tombstoneURL)
    }
}

private struct RecognitionStudyLocalCapturePayload {
    let packetData: Data
    let envelopeData: Data
    let packet: ChordInkCanonicalTrajectoryPacket
    let envelope: RecognitionStudyCaptureEnvelope
}

private struct RecognitionStudyLocalCaptureBundle {
    let directory: URL
    let packetData: Data
    let envelopeData: Data
    let commitData: Data
    let packet: ChordInkCanonicalTrajectoryPacket
    let envelope: RecognitionStudyCaptureEnvelope
    let commit: RecognitionStudyLocalCaptureCommitMarker
}

private struct RecognitionStudyLocalCaptureCommitMarker:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let schemaVersionValue = "recognition-study-local-commit-v1"
    static let maximumCanonicalJSONByteCount =
        RecognitionStudyCaptureLimits.maximumCommitMarkerByteCount

    let schemaVersion: RecognitionStudyPrintableASCII
    let localSessionID: RecognitionStudyCanonicalUUID
    let authorizationID: RecognitionStudyCanonicalUUID
    let localCaptureID: RecognitionStudyCanonicalUUID
    let trajectorySHA256: RecognitionStudySHA256
    let trajectoryByteCount: UInt64
    let envelopeSHA256: RecognitionStudySHA256
    let envelopeByteCount: UInt64

    init(
        packetData: Data,
        envelopeData: Data,
        envelope: RecognitionStudyCaptureEnvelope
    ) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.schemaVersionValue,
            maximumUTF8ByteCount: 64
        )
        localSessionID = envelope.localSessionID
        authorizationID = envelope.authorizationBinding.authorizationID
        localCaptureID = envelope.localCaptureID
        trajectorySHA256 = RecognitionStudySHA256(digesting: packetData)
        trajectoryByteCount = UInt64(packetData.count)
        envelopeSHA256 = RecognitionStudySHA256(digesting: envelopeData)
        envelopeByteCount = UInt64(envelopeData.count)
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyLocalCaptureStoreWire.CommitMarker.self,
            construct: { Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyLocalCaptureStoreWire.CommitMarker
    ) {
        schemaVersion = wire.schemaVersion
        localSessionID = wire.localSessionID
        authorizationID = wire.authorizationID
        localCaptureID = wire.localCaptureID
        trajectorySHA256 = wire.trajectorySHA256
        trajectoryByteCount = wire.trajectoryByteCount
        envelopeSHA256 = wire.envelopeSHA256
        envelopeByteCount = wire.envelopeByteCount
    }

    func validateContract() throws {
        guard schemaVersion.rawValue == Self.schemaVersionValue else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "commit schemaVersion"
            )
        }
        guard trajectoryByteCount > 0,
              trajectoryByteCount
                <= UInt64(RecognitionStudyCaptureLimits.maximumCanonicalPacketByteCount) else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "commit trajectoryByteCount"
            )
        }
        guard envelopeByteCount > 0,
              envelopeByteCount <= UInt64(
                RecognitionStudyCaptureEnvelope.maximumCanonicalJSONByteCount
              ) else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "commit envelopeByteCount"
            )
        }
    }
}

private struct RecognitionStudySessionDeletionTombstone:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let schemaVersionValue = "recognition-study-session-deletion-v1"
    static let maximumCanonicalJSONByteCount =
        RecognitionStudyCaptureLimits.maximumCommitMarkerByteCount

    let schemaVersion: RecognitionStudyPrintableASCII
    let localSessionID: RecognitionStudyCanonicalUUID
    let sessionManifestSHA256: RecognitionStudySHA256
    let clientRequestedAtUnixMilliseconds: Int64

    init(
        manifest: RecognitionStudySessionManifest,
        clientRequestedAtUnixMilliseconds: Int64
    ) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.schemaVersionValue,
            maximumUTF8ByteCount: 64
        )
        localSessionID = manifest.localSessionID
        sessionManifestSHA256 = RecognitionStudySHA256(
            digesting: try manifest.canonicalData()
        )
        self.clientRequestedAtUnixMilliseconds =
            clientRequestedAtUnixMilliseconds
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType:
                RecognitionStudyLocalCaptureStoreWire.DeletionTombstone.self,
            construct: { Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyLocalCaptureStoreWire.DeletionTombstone
    ) {
        schemaVersion = wire.schemaVersion
        localSessionID = wire.localSessionID
        sessionManifestSHA256 = wire.sessionManifestSHA256
        clientRequestedAtUnixMilliseconds =
            wire.clientRequestedAtUnixMilliseconds
    }

    func validateContract() throws {
        guard schemaVersion.rawValue == Self.schemaVersionValue else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "deletion tombstone schemaVersion"
            )
        }
    }
}

fileprivate enum RecognitionStudyLocalCaptureStoreWire {
    struct CommitMarker: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let localSessionID: RecognitionStudyCanonicalUUID
        let authorizationID: RecognitionStudyCanonicalUUID
        let localCaptureID: RecognitionStudyCanonicalUUID
        let trajectorySHA256: RecognitionStudySHA256
        let trajectoryByteCount: UInt64
        let envelopeSHA256: RecognitionStudySHA256
        let envelopeByteCount: UInt64
    }

    struct DeletionTombstone: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let localSessionID: RecognitionStudyCanonicalUUID
        let sessionManifestSHA256: RecognitionStudySHA256
        let clientRequestedAtUnixMilliseconds: Int64
    }
}

private extension RecognitionStudyLocalCaptureStore {
    func refreshBeforeOperation() throws {
        if !hasStarted {
            try recover()
            return
        }
        try requireProtectedData()
        try recoverDeletionTombstones()
        try recoverSessions()
    }

    func bootstrapDirectories() throws {
        try createProtectedDirectory(storeDirectory)
        try createProtectedDirectory(sessionsDirectory)
        try createProtectedDirectory(tombstonesDirectory)
        try createProtectedDirectory(quarantineDirectory)
    }

    func requireProtectedData() throws {
        guard hooks.isProtectedDataAvailable() else {
            throw RecognitionStudyLocalCaptureStoreError
                .protectedDataUnavailable
        }
    }

    func performIO<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch {
            if hooks.classifiesProtectedDataError(error) {
                throw RecognitionStudyLocalCaptureStoreError
                    .protectedDataUnavailable
            }
            throw error
        }
    }

    func isProtectedDataError(_ error: Error) -> Bool {
        if let storeError = error as? RecognitionStudyLocalCaptureStoreError,
           storeError == .protectedDataUnavailable {
            return true
        }
        return hooks.classifiesProtectedDataError(error)
    }

    func createProtectedDirectory(_ url: URL) throws {
        try requireProtectedData()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue, try !isSymbolicLink(url) else {
                throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                    "expected directory at \(url.lastPathComponent)"
                )
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
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "refusing to overwrite \(url.lastPathComponent)"
            )
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

    /// Some platforms do not support synchronizing a directory handle. The
    /// request remains observable, and only known unsupported POSIX results
    /// are ignored; protected-data errors remain retryable.
    func synchronizeDirectoryIfSupported(_ url: URL) throws {
        hooks.observePolicyRequest(.synchronize(url))
        do {
            try performIO {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.synchronize()
            }
        } catch {
            if isProtectedDataError(error) {
                throw RecognitionStudyLocalCaptureStoreError
                    .protectedDataUnavailable
            }
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain,
               [9, 21, 22].contains(nsError.code) {
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
               let underlying = nsError.userInfo[NSUnderlyingErrorKey]
                    as? NSError,
               underlying.domain == NSPOSIXErrorDomain,
               [0, 2, 9, 21, 22].contains(underlying.code) {
                return
            }
            throw error
        }
    }

    func sessionDirectory(_ sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
    }

    func tombstoneURL(_ sessionID: String) -> URL {
        tombstonesDirectory.appendingPathComponent("\(sessionID).json")
    }

    func loadSessionManifest(
        from directory: URL
    ) throws -> RecognitionStudySessionManifest {
        let data = try readCappedData(
            at: directory.appendingPathComponent(Self.sessionFileName),
            maximumByteCount:
                RecognitionStudySessionManifest.maximumCanonicalJSONByteCount,
            artifactName: Self.sessionFileName
        )
        return try RecognitionStudySessionManifest.decodeCanonicalData(data)
    }

    func validSessionManifests() throws -> [RecognitionStudySessionManifest] {
        var manifests: [RecognitionStudySessionManifest] = []
        for directory in try childDirectories(of: sessionsDirectory) {
            let sessionID = directory.lastPathComponent
            guard isCanonicalUUIDPathComponent(sessionID),
                  !fileManager.fileExists(atPath: tombstoneURL(sessionID).path) else {
                continue
            }
            do {
                let manifest = try loadSessionManifest(from: directory)
                guard manifest.localSessionID.rawValue == sessionID else {
                    continue
                }
                manifests.append(manifest)
            } catch {
                if isProtectedDataError(error) {
                    throw error
                }
            }
        }
        return manifests
    }

    func recoverDeletionTombstones() throws {
        for url in try childItems(of: tombstonesDirectory) {
            guard try isRegularFile(url), url.pathExtension == "json" else {
                try quarantineGlobalItem(url, reason: "invalid-tombstone-item")
                continue
            }
            do {
                _ = try loadDeletionTombstone(from: url)
                try completeDeletion(tombstoneURL: url)
            } catch {
                if isProtectedDataError(error) {
                    throw error
                }
                try quarantineGlobalItem(url, reason: "invalid-tombstone")
            }
        }
    }

    func loadDeletionTombstone(
        from url: URL
    ) throws -> RecognitionStudySessionDeletionTombstone {
        let data = try readCappedData(
            at: url,
            maximumByteCount:
                RecognitionStudySessionDeletionTombstone
                    .maximumCanonicalJSONByteCount,
            artifactName: "deletion tombstone"
        )
        let tombstone = try RecognitionStudySessionDeletionTombstone
            .decodeCanonicalData(data)
        guard url.deletingPathExtension().lastPathComponent
                == tombstone.localSessionID.rawValue else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "deletion tombstone filename"
            )
        }
        return tombstone
    }

    func completeDeletion(tombstoneURL: URL) throws {
        let tombstone = try loadDeletionTombstone(from: tombstoneURL)
        let directory = sessionDirectory(tombstone.localSessionID.rawValue)
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        let manifest = try loadSessionManifest(from: directory)
        let digest = RecognitionStudySHA256(
            digesting: try manifest.canonicalData()
        )
        guard manifest.localSessionID == tombstone.localSessionID,
              digest == tombstone.sessionManifestSHA256 else {
            try quarantineGlobalItem(directory, reason: "deletion-mismatch")
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "deletion tombstone does not bind the session"
            )
        }
        try performIO {
            try fileManager.removeItem(at: directory)
        }
        try synchronizeDirectoryIfSupported(sessionsDirectory)
    }

    func recoverSessions() throws {
        var validSessionDirectories: [URL] = []
        for directory in try childItems(of: sessionsDirectory) {
            guard try isDirectory(directory),
                  isCanonicalUUIDPathComponent(directory.lastPathComponent) else {
                try quarantineGlobalItem(directory, reason: "invalid-session")
                continue
            }
            let sessionID = directory.lastPathComponent
            guard !fileManager.fileExists(atPath: tombstoneURL(sessionID).path) else {
                continue
            }
            do {
                let manifest = try loadSessionManifest(from: directory)
                guard manifest.localSessionID.rawValue == sessionID else {
                    throw RecognitionStudyLocalCaptureStoreError
                        .corruptArtifact("session directory identity")
                }
                try ensureSessionSubdirectories(directory)
                try recoverStaging(in: directory, session: manifest)
                _ = try validCommittedBundles(in: directory, manifest: manifest)
                validSessionDirectories.append(directory)
            } catch {
                if isProtectedDataError(error) {
                    throw error
                }
                try quarantineGlobalItem(directory, reason: "corrupt-session")
            }
        }
        try enforceGlobalUniqueness(in: validSessionDirectories)
        try enforceExistingQuotas(in: validSessionDirectories)
    }

    func ensureSessionSubdirectories(_ sessionDirectory: URL) throws {
        try createProtectedDirectory(
            sessionDirectory.appendingPathComponent(
                Self.capturesDirectoryName,
                isDirectory: true
            )
        )
        try createProtectedDirectory(
            sessionDirectory.appendingPathComponent(
                Self.stagingDirectoryName,
                isDirectory: true
            )
        )
        try createProtectedDirectory(
            sessionDirectory.appendingPathComponent(
                Self.sessionQuarantineDirectoryName,
                isDirectory: true
            )
        )
    }

    func recoverStaging(
        in sessionDirectory: URL,
        session: RecognitionStudySessionManifest
    ) throws {
        let stagingRoot = sessionDirectory.appendingPathComponent(
            Self.stagingDirectoryName,
            isDirectory: true
        )
        for stagingDirectory in try childItems(of: stagingRoot) {
            let authorizationKey = stagingDirectory.lastPathComponent
            guard try isDirectory(stagingDirectory),
                  isCanonicalUUIDPathComponent(authorizationKey) else {
                try quarantineSessionItem(
                    stagingDirectory,
                    sessionDirectory: sessionDirectory,
                    reason: "invalid-stage"
                )
                continue
            }
            let commitURL = stagingDirectory.appendingPathComponent(
                Self.commitFileName
            )
            guard fileManager.fileExists(atPath: commitURL.path) else {
                try quarantineSessionItem(
                    stagingDirectory,
                    sessionDirectory: sessionDirectory,
                    reason: "incomplete-stage"
                )
                continue
            }
            do {
                let staged = try loadCommittedBundle(
                    from: stagingDirectory,
                    session: session,
                    expectedAuthorizationKey: authorizationKey
                )
                let finalDirectory = sessionDirectory
                    .appendingPathComponent(
                        Self.capturesDirectoryName,
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        authorizationKey,
                        isDirectory: true
                    )
                if fileManager.fileExists(atPath: finalDirectory.path) {
                    let final = try loadCommittedBundle(
                        from: finalDirectory,
                        session: session,
                        expectedAuthorizationKey: authorizationKey
                    )
                    if final.packetData == staged.packetData,
                       final.envelopeData == staged.envelopeData,
                       final.commitData == staged.commitData {
                        try performIO {
                            try fileManager.removeItem(at: stagingDirectory)
                        }
                        try synchronizeDirectoryIfSupported(stagingRoot)
                    } else {
                        try quarantineSessionItem(
                            stagingDirectory,
                            sessionDirectory: sessionDirectory,
                            reason: "conflicting-stage"
                        )
                    }
                    continue
                }
                let finalCount = try validCommittedBundles(
                    in: sessionDirectory,
                    manifest: session
                ).count
                guard finalCount < Int(quotas.maximumCapturesPerSession),
                      try uniquenessConflict(for: staged.envelope) == nil else {
                    try quarantineSessionItem(
                        stagingDirectory,
                        sessionDirectory: sessionDirectory,
                        reason: "stage-identity-conflict"
                    )
                    continue
                }
                try performIO {
                    try fileManager.moveItem(
                        at: stagingDirectory,
                        to: finalDirectory
                    )
                }
                try synchronizeDirectoryIfSupported(
                    finalDirectory.deletingLastPathComponent()
                )
            } catch {
                if isProtectedDataError(error) {
                    throw error
                }
                try quarantineSessionItem(
                    stagingDirectory,
                    sessionDirectory: sessionDirectory,
                    reason: "corrupt-stage"
                )
            }
        }
    }

    func validCommittedBundles(
        in sessionDirectory: URL,
        manifest: RecognitionStudySessionManifest
    ) throws -> [RecognitionStudyLocalCaptureBundle] {
        let capturesRoot = sessionDirectory.appendingPathComponent(
            Self.capturesDirectoryName,
            isDirectory: true
        )
        var bundles: [RecognitionStudyLocalCaptureBundle] = []
        for directory in try childItems(of: capturesRoot) {
            let authorizationKey = directory.lastPathComponent
            guard try isDirectory(directory),
                  isCanonicalUUIDPathComponent(authorizationKey) else {
                try quarantineSessionItem(
                    directory,
                    sessionDirectory: sessionDirectory,
                    reason: "invalid-final"
                )
                continue
            }
            do {
                bundles.append(
                    try loadCommittedBundle(
                        from: directory,
                        session: manifest,
                        expectedAuthorizationKey: authorizationKey
                    )
                )
            } catch {
                if isProtectedDataError(error) {
                    throw error
                }
                try quarantineSessionItem(
                    directory,
                    sessionDirectory: sessionDirectory,
                    reason: "corrupt-final"
                )
            }
        }
        if bundles.count > Int(quotas.maximumCapturesPerSession) {
            for bundle in bundles.dropFirst(
                Int(quotas.maximumCapturesPerSession)
            ) {
                try quarantineSessionItem(
                    bundle.directory,
                    sessionDirectory: sessionDirectory,
                    reason: "capture-count-overflow"
                )
            }
            bundles.removeLast(
                bundles.count - Int(quotas.maximumCapturesPerSession)
            )
        }
        return bundles
    }

    func loadStagedPayload(
        from directory: URL,
        session: RecognitionStudySessionManifest,
        expectedAuthorizationKey: String
    ) throws -> RecognitionStudyLocalCapturePayload {
        try requireExactItemNames(
            in: directory,
            expected: [Self.trajectoryFileName, Self.envelopeFileName]
        )
        return try decodePayload(
            from: directory,
            session: session,
            expectedAuthorizationKey: expectedAuthorizationKey
        )
    }

    func loadCommittedBundle(
        from directory: URL,
        session: RecognitionStudySessionManifest,
        expectedAuthorizationKey: String
    ) throws -> RecognitionStudyLocalCaptureBundle {
        try requireExactItemNames(
            in: directory,
            expected: [
                Self.trajectoryFileName,
                Self.envelopeFileName,
                Self.commitFileName
            ]
        )
        let payload = try decodePayload(
            from: directory,
            session: session,
            expectedAuthorizationKey: expectedAuthorizationKey
        )
        let commitData = try readCappedData(
            at: directory.appendingPathComponent(Self.commitFileName),
            maximumByteCount:
                RecognitionStudyLocalCaptureCommitMarker
                    .maximumCanonicalJSONByteCount,
            artifactName: Self.commitFileName
        )
        let commit = try RecognitionStudyLocalCaptureCommitMarker
            .decodeCanonicalData(commitData)
        guard commit.localSessionID == payload.envelope.localSessionID,
              commit.authorizationID
                == payload.envelope.authorizationBinding.authorizationID,
              commit.localCaptureID == payload.envelope.localCaptureID,
              commit.trajectoryByteCount == UInt64(payload.packetData.count),
              commit.envelopeByteCount == UInt64(payload.envelopeData.count),
              commit.trajectorySHA256
                == RecognitionStudySHA256(digesting: payload.packetData),
              commit.envelopeSHA256
                == RecognitionStudySHA256(digesting: payload.envelopeData) else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "commit marker binding"
            )
        }
        return RecognitionStudyLocalCaptureBundle(
            directory: directory,
            packetData: payload.packetData,
            envelopeData: payload.envelopeData,
            commitData: commitData,
            packet: payload.packet,
            envelope: payload.envelope,
            commit: commit
        )
    }

    func decodePayload(
        from directory: URL,
        session: RecognitionStudySessionManifest,
        expectedAuthorizationKey: String
    ) throws -> RecognitionStudyLocalCapturePayload {
        let packetData = try readCappedData(
            at: directory.appendingPathComponent(Self.trajectoryFileName),
            maximumByteCount:
                RecognitionStudyCaptureLimits.maximumCanonicalPacketByteCount,
            artifactName: Self.trajectoryFileName
        )
        try RecognitionStudyCaptureLimits
            .validateCanonicalPacketByteCountBeforeDecoding(packetData.count)
        let packet = try ChordInkCanonicalTrajectoryPacket
            .decodeCanonicalData(packetData)

        let envelopeData = try readCappedData(
            at: directory.appendingPathComponent(Self.envelopeFileName),
            maximumByteCount:
                RecognitionStudyCaptureEnvelope.maximumCanonicalJSONByteCount,
            artifactName: Self.envelopeFileName
        )
        let envelope = try RecognitionStudyCaptureEnvelope
            .decodeCanonicalData(envelopeData)
        guard envelope.authorizationBinding.kind
                == .localEngineeringDryRunV1,
              envelope.authorizationBinding.authorityArtifactSHA256 == nil,
              envelope.authorizationBinding.authorizationID.rawValue
                == expectedAuthorizationKey else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "authorization binding"
            )
        }
        try envelope.validateBindings(to: session, packet: packet)
        return RecognitionStudyLocalCapturePayload(
            packetData: packetData,
            envelopeData: envelopeData,
            packet: packet,
            envelope: envelope
        )
    }

    func readCappedData(
        at url: URL,
        maximumByteCount: Int,
        artifactName: String
    ) throws -> Data {
        try requireProtectedData()
        guard try isRegularFile(url), try !isSymbolicLink(url) else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "missing or non-regular \(artifactName)"
            )
        }
        let attributes = try performIO {
            try fileManager.attributesOfItem(atPath: url.path)
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard size <= UInt64(maximumByteCount) else {
            throw RecognitionStudyLocalCaptureStoreError.artifactTooLarge(
                name: artifactName,
                maximum: UInt64(maximumByteCount),
                actual: size
            )
        }
        let data = try performIO { try Data(contentsOf: url) }
        guard data.count <= maximumByteCount else {
            throw RecognitionStudyLocalCaptureStoreError.artifactTooLarge(
                name: artifactName,
                maximum: UInt64(maximumByteCount),
                actual: UInt64(data.count)
            )
        }
        return data
    }

    func requireExactItemNames(in directory: URL, expected: Set<String>) throws {
        let actual = Set(try childItems(of: directory).map(\.lastPathComponent))
        guard actual == expected else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "unexpected files in \(directory.lastPathComponent)"
            )
        }
    }

    func committedBundle(
        authorizationKey: String
    ) throws -> RecognitionStudyLocalCaptureBundle? {
        for manifest in try validSessionManifests() {
            let directory = sessionDirectory(manifest.localSessionID.rawValue)
                .appendingPathComponent(
                    Self.capturesDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(authorizationKey, isDirectory: true)
            guard fileManager.fileExists(atPath: directory.path) else {
                continue
            }
            return try loadCommittedBundle(
                from: directory,
                session: manifest,
                expectedAuthorizationKey: authorizationKey
            )
        }
        return nil
    }

    func requireUniqueCaptureIdentity(
        for envelope: RecognitionStudyCaptureEnvelope
    ) throws {
        if let conflict = try uniquenessConflict(for: envelope) {
            throw conflict
        }
    }

    func uniquenessConflict(
        for envelope: RecognitionStudyCaptureEnvelope
    ) throws -> RecognitionStudyLocalCaptureStoreError? {
        for manifest in try validSessionManifests() {
            let directory = sessionDirectory(manifest.localSessionID.rawValue)
            for bundle in try validCommittedBundles(
                in: directory,
                manifest: manifest
            ) {
                if bundle.envelope.authorizationBinding.authorizationID
                    == envelope.authorizationBinding.authorizationID {
                    return .authorizationConflict(
                        envelope.authorizationBinding.authorizationID.rawValue
                    )
                }
                if bundle.envelope.localCaptureID == envelope.localCaptureID {
                    return .captureIDConflict(envelope.localCaptureID.rawValue)
                }
                if bundle.envelope.localSessionID == envelope.localSessionID,
                   bundle.envelope.captureOrdinal == envelope.captureOrdinal {
                    return .captureOrdinalConflict(envelope.captureOrdinal)
                }
            }
        }
        return nil
    }

    func enforceGlobalUniqueness(in sessionDirectories: [URL]) throws {
        var authorizationIDs = Set<String>()
        var captureIDs = Set<String>()
        var ordinals = Set<String>()
        for directory in sessionDirectories.sorted(by: { $0.path < $1.path }) {
            let manifest = try loadSessionManifest(from: directory)
            let bundles = try validCommittedBundles(
                in: directory,
                manifest: manifest
            ).sorted { $0.directory.path < $1.directory.path }
            for bundle in bundles {
                let authorizationID = bundle.envelope.authorizationBinding
                    .authorizationID.rawValue
                let captureID = bundle.envelope.localCaptureID.rawValue
                let ordinal = "\(manifest.localSessionID.rawValue):\(bundle.envelope.captureOrdinal)"
                guard authorizationIDs.insert(authorizationID).inserted,
                      captureIDs.insert(captureID).inserted,
                      ordinals.insert(ordinal).inserted else {
                    try quarantineSessionItem(
                        bundle.directory,
                        sessionDirectory: directory,
                        reason: "duplicate-identity"
                    )
                    continue
                }
            }
        }
    }

    func enforceExistingQuotas(in sessionDirectories: [URL]) throws {
        try requireLimit(
            UInt64(sessionDirectories.count),
            maximum: UInt64(quotas.maximumSessionCount),
            field: "sessionCount"
        )
        for directory in sessionDirectories {
            try requireLimit(
                try directoryByteCount(directory),
                maximum: quotas.maximumSessionByteCount,
                field: "sessionByteCount"
            )
        }
        try requireLimit(
            try directoryByteCount(storeDirectory),
            maximum: quotas.maximumStoreByteCount,
            field: "storeByteCount"
        )
    }

    func requireStoreCapacity(adding addedBytes: UInt64) throws {
        let current = try directoryByteCount(storeDirectory)
        let (total, overflowed) = current.addingReportingOverflow(addedBytes)
        guard !overflowed else {
            throw RecognitionStudyLocalCaptureStoreError.quotaExceeded(
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
        _ value: UInt64,
        maximum: UInt64,
        field: String
    ) throws {
        guard value <= maximum else {
            throw RecognitionStudyLocalCaptureStoreError.quotaExceeded(
                field: field,
                maximum: maximum,
                actual: value
            )
        }
    }

    func directoryByteCount(_ directory: URL) throws -> UInt64 {
        guard fileManager.fileExists(atPath: directory.path) else {
            return 0
        }
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else {
            throw RecognitionStudyLocalCaptureStoreError.corruptArtifact(
                "cannot enumerate \(directory.lastPathComponent)"
            )
        }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try performIO { try url.resourceValues(forKeys: Set(keys)) }
            guard values.isSymbolicLink != true,
                  values.isRegularFile == true else {
                continue
            }
            let size = UInt64(values.fileSize ?? 0)
            let (next, overflowed) = total.addingReportingOverflow(size)
            guard !overflowed else {
                return UInt64.max
            }
            total = next
        }
        return total
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
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    func childDirectories(of directory: URL) throws -> [URL] {
        try childItems(of: directory).filter { try isDirectory($0) }
    }

    func isDirectory(_ url: URL) throws -> Bool {
        let values = try performIO {
            try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    func isRegularFile(_ url: URL) throws -> Bool {
        let values = try performIO {
            try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    func isSymbolicLink(_ url: URL) throws -> Bool {
        try performIO {
            try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                .isSymbolicLink == true
        }
    }

    func isCanonicalUUIDPathComponent(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else {
            return false
        }
        return RecognitionStudyCanonicalUUID(uuid).rawValue == value
    }

    func quarantineSessionItem(
        _ source: URL,
        sessionDirectory: URL,
        reason: String
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }
        let quarantine = sessionDirectory.appendingPathComponent(
            Self.sessionQuarantineDirectoryName,
            isDirectory: true
        )
        try createProtectedDirectory(quarantine)
        let destination = quarantine.appendingPathComponent(
            "\(source.lastPathComponent).\(reason).\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try performIO { try fileManager.moveItem(at: source, to: destination) }
        try applyStoragePolicyRecursively(to: destination)
        try synchronizeDirectoryIfSupported(quarantine)
    }

    func quarantineGlobalItem(_ source: URL, reason: String) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }
        let destination = quarantineDirectory.appendingPathComponent(
            "\(source.lastPathComponent).\(reason).\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try performIO { try fileManager.moveItem(at: source, to: destination) }
        try applyStoragePolicyRecursively(to: destination)
        try synchronizeDirectoryIfSupported(quarantineDirectory)
    }

    func applyStoragePolicyRecursively(to root: URL) throws {
        try applyStoragePolicy(to: root)
        guard try isDirectory(root) else {
            return
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for case let url as URL in enumerator {
            try applyStoragePolicy(to: url)
        }
    }
}
