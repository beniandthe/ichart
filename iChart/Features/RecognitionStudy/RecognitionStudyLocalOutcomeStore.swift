import Foundation

enum RecognitionStudyLocalOutcomeStoreError: Error, Equatable {
    case protectedDataUnavailable
    case outcomeConflict(String)
    case captureIDConflict(String)
    case quotaExceeded(field: String, maximum: UInt64, actual: UInt64)
    case artifactTooLarge(name: String, maximum: UInt64, actual: UInt64)
    case corruptArtifact(String)
}

enum RecognitionStudyLocalOutcomeStoreFaultPoint: String, Sendable {
    case afterStagedOutcomeVerificationBeforeCommitMarker
    case afterCommitMarkerSynchronizationBeforePromotion
}

enum RecognitionStudyLocalOutcomeStorePolicyRequest: Equatable, Sendable {
    case completeFileProtection(URL)
    case excludeFromBackup(URL)
    case synchronize(URL)
}

struct RecognitionStudyLocalOutcomeStoreHooks: Sendable {
    var isProtectedDataAvailable: @Sendable () -> Bool
    var classifiesProtectedDataError: @Sendable (Error) -> Bool
    var observePolicyRequest:
        @Sendable (RecognitionStudyLocalOutcomeStorePolicyRequest) -> Void
    var injectFault:
        @Sendable (RecognitionStudyLocalOutcomeStoreFaultPoint) throws -> Void

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
                RecognitionStudyLocalOutcomeStorePolicyRequest
            ) -> Void = { _ in },
        injectFault:
            @escaping @Sendable (
                RecognitionStudyLocalOutcomeStoreFaultPoint
            ) throws -> Void = { _ in }
    ) {
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.classifiesProtectedDataError = classifiesProtectedDataError
        self.observePolicyRequest = observePolicyRequest
        self.injectFault = injectFault
    }
}

struct RecognitionStudyLocalOutcomeStoreQuotas: Equatable, Sendable {
    let maximumOutcomeCount: UInt32
    let maximumStoreByteCount: UInt64

    static let contract = Self(
        uncheckedMaximumOutcomeCount: 8_192,
        maximumStoreByteCount: 64 * 1024 * 1024
    )

    init(
        maximumOutcomeCount: UInt32,
        maximumStoreByteCount: UInt64
    ) throws {
        guard maximumOutcomeCount > 0, maximumOutcomeCount <= 8_192 else {
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
                "invalid maximumOutcomeCount"
            )
        }
        guard maximumStoreByteCount > 0,
              maximumStoreByteCount <= 64 * 1024 * 1024 else {
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
                "invalid maximumStoreByteCount"
            )
        }
        self.maximumOutcomeCount = maximumOutcomeCount
        self.maximumStoreByteCount = maximumStoreByteCount
    }

    private init(
        uncheckedMaximumOutcomeCount: UInt32,
        maximumStoreByteCount: UInt64
    ) {
        maximumOutcomeCount = uncheckedMaximumOutcomeCount
        self.maximumStoreByteCount = maximumStoreByteCount
    }
}

/// A separate local-only semantic store. It never writes into the trajectory
/// store and exposes no export, telemetry, corpus, upload, or generic save API.
/// Its artifacts are self-reported engineering outcomes, not consented data or
/// independently adjudicated ground truth.
actor RecognitionStudyLocalOutcomeStore {
    static let storeDirectoryName = "recognition-study-outcome-store-v1"

    private static let outcomesDirectoryName = "outcomes"
    private static let stagingDirectoryName = "staging"
    private static let quarantineDirectoryName = "quarantine"
    private static let outcomeFileName = "outcome.json"
    private static let commitFileName = "commit.json"

    private let fileManager = FileManager()
    private let hooks: RecognitionStudyLocalOutcomeStoreHooks
    private let quotas: RecognitionStudyLocalOutcomeStoreQuotas
    private let storeDirectory: URL
    private let outcomesDirectory: URL
    private let stagingDirectory: URL
    private let quarantineDirectory: URL
    private var hasStarted = false

    private init(
        rootDirectory: URL,
        hooks: RecognitionStudyLocalOutcomeStoreHooks,
        quotas: RecognitionStudyLocalOutcomeStoreQuotas
    ) {
        self.hooks = hooks
        self.quotas = quotas
        storeDirectory = rootDirectory.appendingPathComponent(
            Self.storeDirectoryName,
            isDirectory: true
        )
        outcomesDirectory = storeDirectory.appendingPathComponent(
            Self.outcomesDirectoryName,
            isDirectory: true
        )
        stagingDirectory = storeDirectory.appendingPathComponent(
            Self.stagingDirectoryName,
            isDirectory: true
        )
        quarantineDirectory = storeDirectory.appendingPathComponent(
            Self.quarantineDirectoryName,
            isDirectory: true
        )
    }

    static func open(
        rootDirectory: URL,
        hooks: RecognitionStudyLocalOutcomeStoreHooks = .init(),
        quotas: RecognitionStudyLocalOutcomeStoreQuotas = .contract
    ) async throws -> RecognitionStudyLocalOutcomeStore {
        let store = RecognitionStudyLocalOutcomeStore(
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
        try recoverStaging()
        _ = try validBundles()
        hasStarted = true
    }

    @discardableResult
    func storeOutcome(
        packet: ChordInkCanonicalTrajectoryPacket,
        envelope: RecognitionStudyCaptureEnvelope,
        promptID: String,
        intendedChord: String,
        writerConfirmationState: RecognitionStudyWriterConfirmationState,
        baseRecognizerOutcome: RecognitionStudyBaseRecognizerOutcome,
        clientRecordedAtUnixMilliseconds: Int64
    ) throws -> RecognitionStudySemanticOutcomeArtifact {
        try refreshBeforeOperation()
        let outcome = try RecognitionStudySemanticOutcomeArtifact(
            packet: packet,
            envelope: envelope,
            promptID: promptID,
            intendedChord: intendedChord,
            writerConfirmationState: writerConfirmationState,
            baseRecognizerOutcome: baseRecognizerOutcome,
            clientRecordedAtUnixMilliseconds:
                clientRecordedAtUnixMilliseconds
        )
        let outcomeData = try outcome.canonicalData()
        let key = outcome.authorizationID.rawValue
        let finalDirectory = outcomesDirectory.appendingPathComponent(
            key,
            isDirectory: true
        )

        if fileManager.fileExists(atPath: finalDirectory.path) {
            let existing = try loadBundle(
                from: finalDirectory,
                expectedAuthorizationKey: key
            )
            guard existing.outcomeData == outcomeData else {
                throw RecognitionStudyLocalOutcomeStoreError
                    .outcomeConflict(key)
            }
            return existing.outcome
        }

        let bundles = try validBundles()
        if bundles.contains(where: {
            $0.outcome.localCaptureID == outcome.localCaptureID
        }) {
            throw RecognitionStudyLocalOutcomeStoreError.captureIDConflict(
                outcome.localCaptureID.rawValue
            )
        }
        try requireLimit(
            UInt64(bundles.count + 1),
            maximum: UInt64(quotas.maximumOutcomeCount),
            field: "outcomeCount"
        )

        let commit = try RecognitionStudyLocalOutcomeCommitMarker(
            outcomeData: outcomeData,
            outcome: outcome
        )
        let commitData = try commit.canonicalData()
        let addedBytes = UInt64(outcomeData.count + commitData.count)
        try requireLimit(
            try directoryByteCount(storeDirectory) + addedBytes,
            maximum: quotas.maximumStoreByteCount,
            field: "storeByteCount"
        )

        let stage = stagingDirectory.appendingPathComponent(
            key,
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: stage.path) else {
            throw RecognitionStudyLocalOutcomeStoreError.outcomeConflict(key)
        }
        try createProtectedDirectory(stage)
        try writeProtected(
            outcomeData,
            to: stage.appendingPathComponent(Self.outcomeFileName)
        )
        let verifiedOutcome = try loadStagedOutcome(
            from: stage,
            expectedAuthorizationKey: key
        )
        guard verifiedOutcome.data == outcomeData else {
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
                "staged outcome differs from requested outcome"
            )
        }
        try hooks.injectFault(
            .afterStagedOutcomeVerificationBeforeCommitMarker
        )

        let verifiedCommit = try RecognitionStudyLocalOutcomeCommitMarker(
            outcomeData: verifiedOutcome.data,
            outcome: verifiedOutcome.outcome
        )
        try writeProtected(
            try verifiedCommit.canonicalData(),
            to: stage.appendingPathComponent(Self.commitFileName)
        )
        let complete = try loadBundle(
            from: stage,
            expectedAuthorizationKey: key
        )
        try synchronizeDirectoryIfSupported(stage)
        try hooks.injectFault(
            .afterCommitMarkerSynchronizationBeforePromotion
        )

        guard !fileManager.fileExists(atPath: finalDirectory.path) else {
            throw RecognitionStudyLocalOutcomeStoreError.outcomeConflict(key)
        }
        try performIO {
            try fileManager.moveItem(at: stage, to: finalDirectory)
        }
        try synchronizeDirectoryIfSupported(outcomesDirectory)
        return complete.outcome
    }

    func outcome(
        authorizationID: UUID
    ) throws -> RecognitionStudySemanticOutcomeArtifact? {
        try refreshBeforeOperation()
        let key = RecognitionStudyCanonicalUUID(authorizationID).rawValue
        let directory = outcomesDirectory.appendingPathComponent(
            key,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: directory.path) else {
            return nil
        }
        return try loadBundle(
            from: directory,
            expectedAuthorizationKey: key
        ).outcome
    }

    func outcomes(
        localSessionID: UUID
    ) throws -> [RecognitionStudySemanticOutcomeArtifact] {
        try refreshBeforeOperation()
        let sessionID = RecognitionStudyCanonicalUUID(localSessionID)
        return try validBundles()
            .map(\.outcome)
            .filter { $0.localSessionID == sessionID }
            .sorted(by: Self.stableOrder)
    }

    func allOutcomes() throws -> [RecognitionStudySemanticOutcomeArtifact] {
        try refreshBeforeOperation()
        return try validBundles().map(\.outcome).sorted(by: Self.stableOrder)
    }

    private static func stableOrder(
        _ lhs: RecognitionStudySemanticOutcomeArtifact,
        _ rhs: RecognitionStudySemanticOutcomeArtifact
    ) -> Bool {
        if lhs.clientRecordedAtUnixMilliseconds
            != rhs.clientRecordedAtUnixMilliseconds {
            return lhs.clientRecordedAtUnixMilliseconds
                < rhs.clientRecordedAtUnixMilliseconds
        }
        return lhs.authorizationID.rawValue < rhs.authorizationID.rawValue
    }
}

private struct RecognitionStudyLoadedOutcome {
    let data: Data
    let outcome: RecognitionStudySemanticOutcomeArtifact
}

private struct RecognitionStudyLocalOutcomeBundle {
    let directory: URL
    let outcomeData: Data
    let commitData: Data
    let outcome: RecognitionStudySemanticOutcomeArtifact
    let commit: RecognitionStudyLocalOutcomeCommitMarker
}

private struct RecognitionStudyLocalOutcomeCommitMarker:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let schemaVersionValue = "recognition-study-outcome-commit-v1"
    static let maximumCanonicalJSONByteCount = 8 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let localSessionID: RecognitionStudyCanonicalUUID
    let localCaptureID: RecognitionStudyCanonicalUUID
    let authorizationID: RecognitionStudyCanonicalUUID
    let outcomeSHA256: RecognitionStudySHA256
    let outcomeByteCount: UInt64

    init(
        outcomeData: Data,
        outcome: RecognitionStudySemanticOutcomeArtifact
    ) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.schemaVersionValue,
            maximumUTF8ByteCount: 64
        )
        localSessionID = outcome.localSessionID
        localCaptureID = outcome.localCaptureID
        authorizationID = outcome.authorizationID
        outcomeSHA256 = RecognitionStudySHA256(digesting: outcomeData)
        outcomeByteCount = UInt64(outcomeData.count)
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyLocalOutcomeStoreWire.CommitMarker.self,
            construct: { Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyLocalOutcomeStoreWire.CommitMarker
    ) {
        schemaVersion = wire.schemaVersion
        localSessionID = wire.localSessionID
        localCaptureID = wire.localCaptureID
        authorizationID = wire.authorizationID
        outcomeSHA256 = wire.outcomeSHA256
        outcomeByteCount = wire.outcomeByteCount
    }

    func validateContract() throws {
        guard schemaVersion.rawValue == Self.schemaVersionValue,
              outcomeByteCount > 0,
              outcomeByteCount <= UInt64(
                  RecognitionStudySemanticOutcomeArtifact
                    .maximumCanonicalJSONByteCount
              ) else {
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
                "outcome commit contract"
            )
        }
    }
}

fileprivate enum RecognitionStudyLocalOutcomeStoreWire {
    struct CommitMarker: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let localSessionID: RecognitionStudyCanonicalUUID
        let localCaptureID: RecognitionStudyCanonicalUUID
        let authorizationID: RecognitionStudyCanonicalUUID
        let outcomeSHA256: RecognitionStudySHA256
        let outcomeByteCount: UInt64
    }
}

private extension RecognitionStudyLocalOutcomeStore {
    func refreshBeforeOperation() throws {
        if !hasStarted {
            try recover()
            return
        }
        try requireProtectedData()
        try recoverStaging()
        _ = try validBundles()
    }

    func bootstrapDirectories() throws {
        try createProtectedDirectory(storeDirectory)
        try createProtectedDirectory(outcomesDirectory)
        try createProtectedDirectory(stagingDirectory)
        try createProtectedDirectory(quarantineDirectory)
    }

    func requireProtectedData() throws {
        guard hooks.isProtectedDataAvailable() else {
            throw RecognitionStudyLocalOutcomeStoreError
                .protectedDataUnavailable
        }
    }

    func performIO<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch {
            if hooks.classifiesProtectedDataError(error) {
                throw RecognitionStudyLocalOutcomeStoreError
                    .protectedDataUnavailable
            }
            throw error
        }
    }

    func isProtectedDataError(_ error: Error) -> Bool {
        if let storeError = error as? RecognitionStudyLocalOutcomeStoreError,
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
                throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
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
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
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

    func synchronizeDirectoryIfSupported(_ url: URL) throws {
        hooks.observePolicyRequest(.synchronize(url))
        do {
            try performIO {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.synchronize()
            }
        } catch {
            if isProtectedDataError(error) { throw error }
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
               ].contains(nsError.code) {
                return
            }
            throw error
        }
    }

    func recoverStaging() throws {
        for item in try childItems(of: stagingDirectory) {
            let key = item.lastPathComponent
            guard try isDirectory(item), isCanonicalUUID(key) else {
                try quarantine(item, reason: "invalid-stage")
                continue
            }
            let commitURL = item.appendingPathComponent(Self.commitFileName)
            guard fileManager.fileExists(atPath: commitURL.path) else {
                try quarantine(item, reason: "incomplete-stage")
                continue
            }
            do {
                let staged = try loadBundle(
                    from: item,
                    expectedAuthorizationKey: key
                )
                let final = outcomesDirectory.appendingPathComponent(
                    key,
                    isDirectory: true
                )
                if fileManager.fileExists(atPath: final.path) {
                    let committed = try loadBundle(
                        from: final,
                        expectedAuthorizationKey: key
                    )
                    if committed.outcomeData == staged.outcomeData,
                       committed.commitData == staged.commitData {
                        try performIO { try fileManager.removeItem(at: item) }
                        try synchronizeDirectoryIfSupported(stagingDirectory)
                    } else {
                        try quarantine(item, reason: "conflicting-stage")
                    }
                    continue
                }
                let existing = try validBundles()
                guard existing.count < Int(quotas.maximumOutcomeCount),
                      !existing.contains(where: {
                          $0.outcome.localCaptureID
                            == staged.outcome.localCaptureID
                      }) else {
                    try quarantine(item, reason: "stage-identity-conflict")
                    continue
                }
                try performIO { try fileManager.moveItem(at: item, to: final) }
                try synchronizeDirectoryIfSupported(outcomesDirectory)
            } catch {
                if isProtectedDataError(error) { throw error }
                try quarantine(item, reason: "corrupt-stage")
            }
        }
    }

    func validBundles() throws -> [RecognitionStudyLocalOutcomeBundle] {
        var bundles: [RecognitionStudyLocalOutcomeBundle] = []
        var captureIDs = Set<String>()
        for item in try childItems(of: outcomesDirectory).sorted(
            by: { $0.lastPathComponent < $1.lastPathComponent }
        ) {
            let key = item.lastPathComponent
            guard try isDirectory(item), isCanonicalUUID(key) else {
                try quarantine(item, reason: "invalid-final")
                continue
            }
            do {
                let bundle = try loadBundle(
                    from: item,
                    expectedAuthorizationKey: key
                )
                guard captureIDs.insert(
                    bundle.outcome.localCaptureID.rawValue
                ).inserted else {
                    try quarantine(item, reason: "duplicate-capture-id")
                    continue
                }
                bundles.append(bundle)
            } catch {
                if isProtectedDataError(error) { throw error }
                try quarantine(item, reason: "corrupt-final")
            }
        }
        if bundles.count > Int(quotas.maximumOutcomeCount) {
            for bundle in bundles.dropFirst(Int(quotas.maximumOutcomeCount)) {
                try quarantine(bundle.directory, reason: "count-overflow")
            }
            bundles.removeLast(
                bundles.count - Int(quotas.maximumOutcomeCount)
            )
        }
        let byteCount = try directoryByteCount(storeDirectory)
        guard byteCount <= quotas.maximumStoreByteCount else {
            throw RecognitionStudyLocalOutcomeStoreError.quotaExceeded(
                field: "storeByteCount",
                maximum: quotas.maximumStoreByteCount,
                actual: byteCount
            )
        }
        return bundles
    }

    func loadStagedOutcome(
        from directory: URL,
        expectedAuthorizationKey: String
    ) throws -> RecognitionStudyLoadedOutcome {
        try requireExactItemNames(
            in: directory,
            expected: [Self.outcomeFileName]
        )
        let data = try readCappedData(
            at: directory.appendingPathComponent(Self.outcomeFileName),
            maximumByteCount:
                RecognitionStudySemanticOutcomeArtifact
                    .maximumCanonicalJSONByteCount,
            artifactName: Self.outcomeFileName
        )
        let outcome = try RecognitionStudySemanticOutcomeArtifact
            .decodeCanonicalData(data)
        guard outcome.authorizationID.rawValue == expectedAuthorizationKey else {
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
                "outcome authorization binding"
            )
        }
        return RecognitionStudyLoadedOutcome(data: data, outcome: outcome)
    }

    func loadBundle(
        from directory: URL,
        expectedAuthorizationKey: String
    ) throws -> RecognitionStudyLocalOutcomeBundle {
        try requireExactItemNames(
            in: directory,
            expected: [Self.outcomeFileName, Self.commitFileName]
        )
        let outcomeData = try readCappedData(
            at: directory.appendingPathComponent(Self.outcomeFileName),
            maximumByteCount:
                RecognitionStudySemanticOutcomeArtifact
                    .maximumCanonicalJSONByteCount,
            artifactName: Self.outcomeFileName
        )
        let outcome = try RecognitionStudySemanticOutcomeArtifact
            .decodeCanonicalData(outcomeData)
        let commitData = try readCappedData(
            at: directory.appendingPathComponent(Self.commitFileName),
            maximumByteCount:
                RecognitionStudyLocalOutcomeCommitMarker
                    .maximumCanonicalJSONByteCount,
            artifactName: Self.commitFileName
        )
        let commit = try RecognitionStudyLocalOutcomeCommitMarker
            .decodeCanonicalData(commitData)
        guard outcome.authorizationID.rawValue == expectedAuthorizationKey,
              commit.authorizationID == outcome.authorizationID,
              commit.localSessionID == outcome.localSessionID,
              commit.localCaptureID == outcome.localCaptureID,
              commit.outcomeByteCount == UInt64(outcomeData.count),
              commit.outcomeSHA256
                == RecognitionStudySHA256(digesting: outcomeData) else {
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
                "outcome commit binding"
            )
        }
        return RecognitionStudyLocalOutcomeBundle(
            directory: directory,
            outcomeData: outcomeData,
            commitData: commitData,
            outcome: outcome,
            commit: commit
        )
    }

    func readCappedData(
        at url: URL,
        maximumByteCount: Int,
        artifactName: String
    ) throws -> Data {
        try requireProtectedData()
        guard try isRegularFile(url), try !isSymbolicLink(url) else {
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
                "missing or non-regular \(artifactName)"
            )
        }
        let attributes = try performIO {
            try fileManager.attributesOfItem(atPath: url.path)
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard size <= UInt64(maximumByteCount) else {
            throw RecognitionStudyLocalOutcomeStoreError.artifactTooLarge(
                name: artifactName,
                maximum: UInt64(maximumByteCount),
                actual: size
            )
        }
        let data = try performIO { try Data(contentsOf: url) }
        guard data.count <= maximumByteCount else {
            throw RecognitionStudyLocalOutcomeStoreError.artifactTooLarge(
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
            throw RecognitionStudyLocalOutcomeStoreError.corruptArtifact(
                "unexpected files in \(directory.lastPathComponent)"
            )
        }
    }

    func childItems(of directory: URL) throws -> [URL] {
        try requireProtectedData()
        return try performIO {
            try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: [.skipsHiddenFiles]
            )
        }
    }

    func isDirectory(_ url: URL) throws -> Bool {
        let values = try performIO {
            try url.resourceValues(forKeys: [.isDirectoryKey])
        }
        return values.isDirectory == true
    }

    func isRegularFile(_ url: URL) throws -> Bool {
        let values = try performIO {
            try url.resourceValues(forKeys: [.isRegularFileKey])
        }
        return values.isRegularFile == true
    }

    func isSymbolicLink(_ url: URL) throws -> Bool {
        let values = try performIO {
            try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        }
        return values.isSymbolicLink == true
    }

    func isCanonicalUUID(_ value: String) -> Bool {
        (try? RecognitionStudyCanonicalUUID(canonicalString: value)) != nil
    }

    func quarantine(_ item: URL, reason: String) throws {
        guard fileManager.fileExists(atPath: item.path) else { return }
        let destination = quarantineDirectory.appendingPathComponent(
            "\(reason)-\(UUID().uuidString.lowercased())-\(item.lastPathComponent)",
            isDirectory: true
        )
        try performIO { try fileManager.moveItem(at: item, to: destination) }
        try applyStoragePolicy(to: destination)
        try synchronizeDirectoryIfSupported(quarantineDirectory)
        if item.deletingLastPathComponent() != quarantineDirectory {
            try synchronizeDirectoryIfSupported(
                item.deletingLastPathComponent()
            )
        }
    }

    func directoryByteCount(_ directory: URL) throws -> UInt64 {
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .isSymbolicLinkKey
            ],
            options: [.skipsHiddenFiles]
        )
        var total: UInt64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try performIO {
                try url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .isSymbolicLinkKey
                ])
            }
            if values.isSymbolicLink == true {
                enumerator?.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            let (next, overflow) = total.addingReportingOverflow(
                UInt64(values.fileSize ?? 0)
            )
            guard !overflow else {
                throw RecognitionStudyLocalOutcomeStoreError.quotaExceeded(
                    field: "storeByteCount",
                    maximum: quotas.maximumStoreByteCount,
                    actual: UInt64.max
                )
            }
            total = next
        }
        return total
    }

    func requireLimit(
        _ actual: UInt64,
        maximum: UInt64,
        field: String
    ) throws {
        guard actual <= maximum else {
            throw RecognitionStudyLocalOutcomeStoreError.quotaExceeded(
                field: field,
                maximum: maximum,
                actual: actual
            )
        }
    }
}
