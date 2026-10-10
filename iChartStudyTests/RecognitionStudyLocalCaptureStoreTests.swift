import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyLocalCaptureStoreTests: XCTestCase {
    func testCommittedCaptureRoundTripAndStoragePolicyRequests() async throws {
        let root = try temporaryRoot()
        let control = StoreTestControl()
        let store = try await openStore(root: root, control: control)
        let sessionID = uuid("10000000-0000-0000-0000-000000000001")
        let authorizationID = uuid("20000000-0000-0000-0000-000000000001")
        let captureID = uuid("30000000-0000-0000-0000-000000000001")
        let session = try sampleSession(id: sessionID)

        let createdSession = try await store.createSession(session)
        XCTAssertEqual(createdSession, session)
        let stored = try await store.storeCapture(
            localSessionID: sessionID,
            authorizationID: authorizationID,
            localCaptureID: captureID,
            captureOrdinal: 0,
            clientCapturedAtUnixMilliseconds: 1_700_000_000_001,
            presentedSurface: try sampleSurface(),
            packet: try samplePacket(x: 1)
        )
        let captures = try await store.committedCaptures(
            localSessionID: sessionID
        )

        XCTAssertEqual(captures, [stored])
        XCTAssertEqual(
            stored.envelope.authorizationBinding.kind,
            .localEngineeringDryRunV1
        )
        XCTAssertNil(
            stored.envelope.authorizationBinding.authorityArtifactSHA256
        )
        let captureDirectory = finalCaptureDirectory(
            root: root,
            sessionID: sessionID,
            authorizationID: authorizationID
        )
        XCTAssertEqual(
            try Set(
                FileManager.default.contentsOfDirectory(
                    atPath: captureDirectory.path
                )
            ),
            ["commit.json", "envelope.json", "trajectory.json"]
        )

        let trajectoryURL = captureDirectory.appendingPathComponent(
            "trajectory.json"
        )
        XCTAssertTrue(
            control.policyRequests.contains { request in
                guard case .completeFileProtection(let url) = request else {
                    return false
                }
                return url.lastPathComponent == "trajectory.json"
            }
        )
        XCTAssertTrue(
            control.policyRequests.contains { request in
                guard case .excludeFromBackup(let url) = request else {
                    return false
                }
                return url.lastPathComponent == "trajectory.json"
            }
        )
        XCTAssertTrue(
            control.policyRequests.contains { request in
                guard case .synchronize(let url) = request else {
                    return false
                }
                return url.lastPathComponent == "trajectory.json"
            }
        )
        XCTAssertEqual(
            try trajectoryURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup,
            true
        )
        let protection = try FileManager.default.attributesOfItem(
            atPath: trajectoryURL.path
        )[.protectionKey] as? FileProtectionType
        if let protection {
            XCTAssertEqual(protection, .complete)
        }
    }

    func testRejectsEmptyAndContractLimitOverflowBeforeCreatingACommit() async throws {
        let root = try temporaryRoot()
        let store = try await openStore(root: root)
        let sessionID = uuid("10000000-0000-0000-0000-000000000002")
        try await store.createSession(try sampleSession(id: sessionID))

        do {
            _ = try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: uuid("20000000-0000-0000-0000-000000000002"),
                localCaptureID: uuid("30000000-0000-0000-0000-000000000002"),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 1,
                presentedSurface: try sampleSurface(),
                packet: try ChordInkCanonicalTrajectoryPacket(strokes: [])
            )
            XCTFail("Empty packets must be rejected.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyCaptureContractError,
                .invariantViolation(
                    "a capture must contain at least one prepared point"
                )
            )
        }

        let tooManyPoints = InkStroke(
            points: (0...Int(
                RecognitionStudyCaptureLimits.maximumPointCountPerStroke
            )).map {
                InkPoint(x: Double($0), y: 1, timeOffset: nil)
            }
        )
        do {
            _ = try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: uuid("20000000-0000-0000-0000-000000000003"),
                localCaptureID: uuid("30000000-0000-0000-0000-000000000003"),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 1,
                presentedSurface: try sampleSurface(),
                packet: try ChordInkCanonicalTrajectoryPacket(
                    strokes: [tooManyPoints]
                )
            )
            XCTFail("Per-stroke point overflow must be rejected.")
        } catch {
            guard case .limitExceeded(let field, _, _) =
                    error as? RecognitionStudyCaptureContractError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(field, "pointCountPerStroke")
        }

        let tooManyStrokes = Array(
            repeating: InkStroke(
                points: [InkPoint(x: 1, y: 1, timeOffset: nil)]
            ),
            count: Int(RecognitionStudyCaptureLimits.maximumStrokeCount) + 1
        )
        do {
            _ = try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: uuid("20000000-0000-0000-0000-000000000020"),
                localCaptureID: uuid("30000000-0000-0000-0000-000000000020"),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 1,
                presentedSurface: try sampleSurface(),
                packet: try ChordInkCanonicalTrajectoryPacket(
                    strokes: tooManyStrokes
                )
            )
            XCTFail("Stroke-count overflow must be rejected.")
        } catch {
            guard case .limitExceeded(let field, _, _) =
                    error as? RecognitionStudyCaptureContractError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(field, "strokeCount")
        }

        let maximumPerStroke = Int(
            RecognitionStudyCaptureLimits.maximumPointCountPerStroke
        )
        let fullStroke = InkStroke(
            points: (0..<maximumPerStroke).map {
                InkPoint(x: Double($0), y: 1, timeOffset: nil)
            }
        )
        let tooManyTotalPoints = Array(repeating: fullStroke, count: 4) + [
            InkStroke(points: [InkPoint(x: 1, y: 1, timeOffset: nil)])
        ]
        do {
            _ = try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: uuid("20000000-0000-0000-0000-000000000021"),
                localCaptureID: uuid("30000000-0000-0000-0000-000000000021"),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 1,
                presentedSurface: try sampleSurface(),
                packet: try ChordInkCanonicalTrajectoryPacket(
                    strokes: tooManyTotalPoints
                )
            )
            XCTFail("Total-point overflow must be rejected.")
        } catch {
            guard case .limitExceeded(let field, _, _) =
                    error as? RecognitionStudyCaptureContractError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(field, "pointCount")
        }

        let captures = try await store.committedCaptures(
            localSessionID: sessionID
        )
        XCTAssertTrue(captures.isEmpty)
    }

    func testIdenticalRetryIsIdempotentAndIdentityReuseConflicts() async throws {
        let root = try temporaryRoot()
        let store = try await openStore(root: root)
        let sessionID = uuid("10000000-0000-0000-0000-000000000003")
        let authorizationID = uuid("20000000-0000-0000-0000-000000000004")
        let captureID = uuid("30000000-0000-0000-0000-000000000004")
        try await store.createSession(try sampleSession(id: sessionID))

        let first = try await store.storeCapture(
            localSessionID: sessionID,
            authorizationID: authorizationID,
            localCaptureID: captureID,
            captureOrdinal: 0,
            clientCapturedAtUnixMilliseconds: 10,
            presentedSurface: try sampleSurface(),
            packet: try samplePacket(x: 1)
        )
        let retry = try await store.storeCapture(
            localSessionID: sessionID,
            authorizationID: authorizationID,
            localCaptureID: captureID,
            captureOrdinal: 0,
            clientCapturedAtUnixMilliseconds: 10,
            presentedSurface: try sampleSurface(),
            packet: try samplePacket(x: 1)
        )
        XCTAssertEqual(first, retry)
        let captures = try await store.committedCaptures(
            localSessionID: sessionID
        )
        XCTAssertEqual(captures.count, 1)

        await assertStoreError(
            .authorizationConflict(
                RecognitionStudyCanonicalUUID(authorizationID).rawValue
            )
        ) {
            try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: authorizationID,
                localCaptureID: captureID,
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 10,
                presentedSurface: try self.sampleSurface(),
                packet: try self.samplePacket(x: 2)
            )
        }

        let secondAuthorization = uuid(
            "20000000-0000-0000-0000-000000000005"
        )
        await assertStoreError(
            .captureIDConflict(
                RecognitionStudyCanonicalUUID(captureID).rawValue
            )
        ) {
            try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: secondAuthorization,
                localCaptureID: captureID,
                captureOrdinal: 1,
                clientCapturedAtUnixMilliseconds: 11,
                presentedSurface: try self.sampleSurface(),
                packet: try self.samplePacket(x: 2)
            )
        }

        await assertStoreError(.captureOrdinalConflict(0)) {
            try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: secondAuthorization,
                localCaptureID: uuid(
                    "30000000-0000-0000-0000-000000000005"
                ),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 11,
                presentedSurface: try self.sampleSurface(),
                packet: try self.samplePacket(x: 2)
            )
        }
    }

    func testConcurrentSameAuthorizationSerializesToOneCommittedCapture() async throws {
        let root = try temporaryRoot()
        let store = try await openStore(root: root)
        let sessionID = uuid("10000000-0000-0000-0000-000000000004")
        let authorizationID = uuid("20000000-0000-0000-0000-000000000006")
        let captureID = uuid("30000000-0000-0000-0000-000000000006")
        let surface = try sampleSurface()
        let packet = try samplePacket(x: 1)
        try await store.createSession(try sampleSession(id: sessionID))

        async let first = store.storeCapture(
            localSessionID: sessionID,
            authorizationID: authorizationID,
            localCaptureID: captureID,
            captureOrdinal: 0,
            clientCapturedAtUnixMilliseconds: 12,
            presentedSurface: surface,
            packet: packet
        )
        async let second = store.storeCapture(
            localSessionID: sessionID,
            authorizationID: authorizationID,
            localCaptureID: captureID,
            captureOrdinal: 0,
            clientCapturedAtUnixMilliseconds: 12,
            presentedSurface: surface,
            packet: packet
        )
        let results = try await (first, second)

        XCTAssertEqual(results.0, results.1)
        let captures = try await store.committedCaptures(
            localSessionID: sessionID
        )
        XCTAssertEqual(captures.count, 1)
    }

    func testFailureBeforeMarkerIsInvisibleAndIncompleteStageIsQuarantined() async throws {
        let root = try temporaryRoot()
        let control = StoreTestControl()
        control.faultPoint = .afterStagedPayloadVerificationBeforeCommitMarker
        let store = try await openStore(root: root, control: control)
        let sessionID = uuid("10000000-0000-0000-0000-000000000005")
        let authorizationID = uuid("20000000-0000-0000-0000-000000000007")
        try await store.createSession(try sampleSession(id: sessionID))

        do {
            _ = try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: authorizationID,
                localCaptureID: uuid("30000000-0000-0000-0000-000000000007"),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 13,
                presentedSurface: try sampleSurface(),
                packet: try samplePacket(x: 1)
            )
            XCTFail("The injected failure must interrupt the transaction.")
        } catch {
            XCTAssertEqual(error as? StoreInjectedFailure, .stop)
        }
        control.faultPoint = nil

        let captures = try await store.committedCaptures(
            localSessionID: sessionID
        )
        XCTAssertTrue(captures.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: finalCaptureDirectory(
                    root: root,
                    sessionID: sessionID,
                    authorizationID: authorizationID
                ).path
            )
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                atPath: stagingRoot(root: root, sessionID: sessionID).path
            ).contains(
                RecognitionStudyCanonicalUUID(authorizationID).rawValue
            )
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                atPath: sessionQuarantine(root: root, sessionID: sessionID).path
            ).isEmpty
        )
    }

    func testCompleteStageRecoveryPromotesAndDeduplicates() async throws {
        let root = try temporaryRoot()
        let control = StoreTestControl()
        control.faultPoint = .afterCommitMarkerSynchronizationBeforePromotion
        let interrupted = try await openStore(root: root, control: control)
        let sessionID = uuid("10000000-0000-0000-0000-000000000006")
        let authorizationID = uuid("20000000-0000-0000-0000-000000000008")
        try await interrupted.createSession(try sampleSession(id: sessionID))

        do {
            _ = try await interrupted.storeCapture(
                localSessionID: sessionID,
                authorizationID: authorizationID,
                localCaptureID: uuid("30000000-0000-0000-0000-000000000008"),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 14,
                presentedSurface: try sampleSurface(),
                packet: try samplePacket(x: 1)
            )
            XCTFail("The injected failure must leave a complete stage.")
        } catch {
            XCTAssertEqual(error as? StoreInjectedFailure, .stop)
        }

        let recovered = try await openStore(root: root)
        let captures = try await recovered.committedCaptures(
            localSessionID: sessionID
        )
        XCTAssertEqual(captures.count, 1)
        let final = finalCaptureDirectory(
            root: root,
            sessionID: sessionID,
            authorizationID: authorizationID
        )
        let duplicateStage = stagingRoot(root: root, sessionID: sessionID)
            .appendingPathComponent(
                RecognitionStudyCanonicalUUID(authorizationID).rawValue,
                isDirectory: true
            )
        try FileManager.default.copyItem(at: final, to: duplicateStage)

        _ = try await openStore(root: root)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: duplicateStage.path)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.path))
    }

    func testInvalidCompleteStageIsQuarantined() async throws {
        let root = try temporaryRoot()
        let control = StoreTestControl()
        control.faultPoint = .afterCommitMarkerSynchronizationBeforePromotion
        let interrupted = try await openStore(root: root, control: control)
        let sessionID = uuid("10000000-0000-0000-0000-000000000007")
        let authorizationID = uuid("20000000-0000-0000-0000-000000000009")
        try await interrupted.createSession(try sampleSession(id: sessionID))

        do {
            _ = try await interrupted.storeCapture(
                localSessionID: sessionID,
                authorizationID: authorizationID,
                localCaptureID: uuid("30000000-0000-0000-0000-000000000009"),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: 15,
                presentedSurface: try sampleSurface(),
                packet: try samplePacket(x: 1)
            )
        } catch {
            XCTAssertEqual(error as? StoreInjectedFailure, .stop)
        }
        let stage = stagingRoot(root: root, sessionID: sessionID)
            .appendingPathComponent(
                RecognitionStudyCanonicalUUID(authorizationID).rawValue,
                isDirectory: true
            )
        try appendWhitespace(
            to: stage.appendingPathComponent("envelope.json")
        )

        let recovered = try await openStore(root: root)
        let captures = try await recovered.committedCaptures(
            localSessionID: sessionID
        )
        XCTAssertTrue(captures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.path))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                atPath: sessionQuarantine(root: root, sessionID: sessionID).path
            ).isEmpty
        )
    }

    func testTamperedPacketEnvelopeAndCommitAreQuarantined() async throws {
        for (index, fileName) in [
            "trajectory.json",
            "envelope.json",
            "commit.json"
        ].enumerated() {
            let root = try temporaryRoot()
            let store = try await openStore(root: root)
            let sessionID = UUID()
            let authorizationID = UUID()
            try await store.createSession(try sampleSession(id: sessionID))
            _ = try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: authorizationID,
                localCaptureID: UUID(),
                captureOrdinal: 0,
                clientCapturedAtUnixMilliseconds: Int64(20 + index),
                presentedSurface: try sampleSurface(),
                packet: try samplePacket(x: Double(index + 1))
            )
            let file = finalCaptureDirectory(
                root: root,
                sessionID: sessionID,
                authorizationID: authorizationID
            ).appendingPathComponent(fileName)
            try appendWhitespace(to: file)

            let captures = try await store.committedCaptures(
                localSessionID: sessionID
            )
            XCTAssertTrue(
                captures.isEmpty,
                "Tampered \(fileName) must not enumerate."
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testOversizedPacketIsRejectedBeforeDecodeAndQuarantined() async throws {
        let root = try temporaryRoot()
        let store = try await openStore(root: root)
        let sessionID = uuid("10000000-0000-0000-0000-000000000008")
        let authorizationID = uuid("20000000-0000-0000-0000-000000000010")
        try await store.createSession(try sampleSession(id: sessionID))
        _ = try await store.storeCapture(
            localSessionID: sessionID,
            authorizationID: authorizationID,
            localCaptureID: uuid("30000000-0000-0000-0000-000000000010"),
            captureOrdinal: 0,
            clientCapturedAtUnixMilliseconds: 30,
            presentedSurface: try sampleSurface(),
            packet: try samplePacket(x: 1)
        )
        let trajectory = finalCaptureDirectory(
            root: root,
            sessionID: sessionID,
            authorizationID: authorizationID
        ).appendingPathComponent("trajectory.json")
        try Data(
            repeating: 0xff,
            count: RecognitionStudyCaptureLimits
                .maximumCanonicalPacketByteCount + 1
        ).write(to: trajectory)

        let captures = try await store.committedCaptures(
            localSessionID: sessionID
        )
        XCTAssertTrue(captures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trajectory.path))
    }

    func testTamperedSessionFailsClosedAndIsQuarantined() async throws {
        let root = try temporaryRoot()
        let store = try await openStore(root: root)
        let sessionID = uuid("10000000-0000-0000-0000-000000000009")
        try await store.createSession(try sampleSession(id: sessionID))
        let sessionFile = sessionDirectory(root: root, sessionID: sessionID)
            .appendingPathComponent("session.json")
        try appendWhitespace(to: sessionFile)

        let manifest = try await store.sessionManifest(
            localSessionID: sessionID
        )
        XCTAssertNil(manifest)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionDirectory(root: root, sessionID: sessionID).path
            )
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                atPath: globalQuarantine(root: root).path
            ).isEmpty
        )
    }

    func testProtectedDataUnavailableIsRetryableAndDoesNotQuarantine() async throws {
        let root = try temporaryRoot()
        let control = StoreTestControl()
        let store = try await openStore(root: root, control: control)
        let sessionID = uuid("10000000-0000-0000-0000-000000000010")
        try await store.createSession(try sampleSession(id: sessionID))
        control.protectedDataAvailable = false

        do {
            _ = try await store.sessionManifest(localSessionID: sessionID)
            XCTFail("Unavailable protected data must be retryable.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyLocalCaptureStoreError,
                .protectedDataUnavailable
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sessionDirectory(root: root, sessionID: sessionID).path
            )
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: globalQuarantine(root: root).path
            ).isEmpty
        )

        control.protectedDataAvailable = true
        let manifest = try await store.sessionManifest(
            localSessionID: sessionID
        )
        XCTAssertNotNil(manifest)
    }

    func testQuotaEnforcementForSessionsCapturesAndBytes() async throws {
        let oneEach = try RecognitionStudyLocalCaptureStoreQuotas(
            maximumCapturesPerSession: 1,
            maximumSessionByteCount: 1024 * 1024,
            maximumStoreByteCount: 2 * 1024 * 1024,
            maximumSessionCount: 1
        )
        let root = try temporaryRoot()
        let store = try await RecognitionStudyLocalCaptureStore.open(
            rootDirectory: root,
            quotas: oneEach
        )
        let sessionID = uuid("10000000-0000-0000-0000-000000000011")
        try await store.createSession(try sampleSession(id: sessionID))
        await assertStoreQuota(field: "sessionCount") {
            try await store.createSession(
                try self.sampleSession(id: UUID())
            )
        }
        _ = try await store.storeCapture(
            localSessionID: sessionID,
            authorizationID: UUID(),
            localCaptureID: UUID(),
            captureOrdinal: 0,
            clientCapturedAtUnixMilliseconds: 40,
            presentedSurface: try sampleSurface(),
            packet: try samplePacket(x: 1)
        )
        await assertStoreQuota(field: "capturesPerSession") {
            try await store.storeCapture(
                localSessionID: sessionID,
                authorizationID: UUID(),
                localCaptureID: UUID(),
                captureOrdinal: 1,
                clientCapturedAtUnixMilliseconds: 41,
                presentedSurface: try self.sampleSurface(),
                packet: try self.samplePacket(x: 2)
            )
        }

        let byteRoot = try temporaryRoot()
        let byteQuotas = try RecognitionStudyLocalCaptureStoreQuotas(
            maximumCapturesPerSession: 1,
            maximumSessionByteCount: 1,
            maximumStoreByteCount: 1,
            maximumSessionCount: 1
        )
        let byteStore = try await RecognitionStudyLocalCaptureStore.open(
            rootDirectory: byteRoot,
            quotas: byteQuotas
        )
        await assertStoreQuota(field: "sessionByteCount") {
            try await byteStore.createSession(
                try self.sampleSession(id: UUID())
            )
        }

        let storeByteRoot = try temporaryRoot()
        let storeByteQuotas = try RecognitionStudyLocalCaptureStoreQuotas(
            maximumCapturesPerSession: 1,
            maximumSessionByteCount: 1024 * 1024,
            maximumStoreByteCount: 1,
            maximumSessionCount: 1
        )
        let storeByteStore = try await RecognitionStudyLocalCaptureStore.open(
            rootDirectory: storeByteRoot,
            quotas: storeByteQuotas
        )
        await assertStoreQuota(field: "storeByteCount") {
            try await storeByteStore.createSession(
                try self.sampleSession(id: UUID())
            )
        }
    }

    func testTombstoneRecoveryDeletesOnlyExactSession() async throws {
        let root = try temporaryRoot()
        let control = StoreTestControl()
        let store = try await openStore(root: root, control: control)
        let deletedID = uuid("10000000-0000-0000-0000-000000000012")
        let retainedID = uuid("10000000-0000-0000-0000-000000000013")
        try await store.createSession(try sampleSession(id: deletedID))
        try await store.createSession(try sampleSession(id: retainedID))
        control.faultPoint = .afterDeletionTombstoneSynchronizationBeforeRemoval

        do {
            try await store.deleteSession(
                localSessionID: deletedID,
                clientRequestedAtUnixMilliseconds: 50
            )
            XCTFail("The deletion fault must leave a tombstone.")
        } catch {
            XCTAssertEqual(error as? StoreInjectedFailure, .stop)
        }
        let tombstone = tombstoneURL(root: root, sessionID: deletedID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tombstone.path))
        XCTAssertTrue(
            control.policyRequests.contains(.completeFileProtection(tombstone))
        )
        XCTAssertTrue(
            control.policyRequests.contains(.excludeFromBackup(tombstone))
        )

        let recovered = try await openStore(root: root)
        let deletedManifest = try await recovered.sessionManifest(
            localSessionID: deletedID
        )
        let retainedManifest = try await recovered.sessionManifest(
            localSessionID: retainedID
        )
        XCTAssertNil(deletedManifest)
        XCTAssertNotNil(retainedManifest)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionDirectory(root: root, sessionID: deletedID).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sessionDirectory(root: root, sessionID: retainedID).path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: tombstone.path))
    }

    private func openStore(
        root: URL,
        control: StoreTestControl = StoreTestControl()
    ) async throws -> RecognitionStudyLocalCaptureStore {
        try await RecognitionStudyLocalCaptureStore.open(
            rootDirectory: root,
            hooks: RecognitionStudyLocalCaptureStoreHooks(
                isProtectedDataAvailable: {
                    control.protectedDataAvailable
                },
                observePolicyRequest: { request in
                    control.record(request)
                },
                injectFault: { point in
                    try control.inject(point)
                }
            )
        )
    }

    private func sampleSession(
        id: UUID
    ) throws -> RecognitionStudySessionManifest {
        try RecognitionStudySessionManifest(
            localSessionID: id,
            clientCreatedAtUnixMilliseconds: 1_700_000_000_000,
            clientAppContext: RecognitionStudyClientAppContext(
                appVersion: "1.0",
                buildNumber: "100",
                operatingSystemMajorVersion: 26,
                operatingSystemMinorVersion: 0
            )
        )
    }

    private func sampleSurface() throws -> RecognitionStudyPresentedSurface {
        try RecognitionStudyPresentedSurface(
            presentedChartStyle: .simpleChordSheet,
            clientObservedOrientation: .portrait,
            canvasWidth: 768,
            canvasHeight: 1024,
            presentedPaceInstruction: .natural,
            presentedSizeInstruction: .normal,
            presentedConstructionInstruction: .rootFirst
        )
    }

    private func samplePacket(
        x: Double
    ) throws -> ChordInkCanonicalTrajectoryPacket {
        try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [InkPoint(x: x, y: 2, timeOffset: 0.25)],
                creationTimeOffset: 0
            )
        ])
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "recognition-study-store-tests-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func storeRoot(_ root: URL) -> URL {
        root.appendingPathComponent(
            RecognitionStudyLocalCaptureStore.storeDirectoryName,
            isDirectory: true
        )
    }

    private func sessionDirectory(root: URL, sessionID: UUID) -> URL {
        storeRoot(root)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(
                RecognitionStudyCanonicalUUID(sessionID).rawValue,
                isDirectory: true
            )
    }

    private func finalCaptureDirectory(
        root: URL,
        sessionID: UUID,
        authorizationID: UUID
    ) -> URL {
        sessionDirectory(root: root, sessionID: sessionID)
            .appendingPathComponent("captures", isDirectory: true)
            .appendingPathComponent(
                RecognitionStudyCanonicalUUID(authorizationID).rawValue,
                isDirectory: true
            )
    }

    private func stagingRoot(root: URL, sessionID: UUID) -> URL {
        sessionDirectory(root: root, sessionID: sessionID)
            .appendingPathComponent("staging", isDirectory: true)
    }

    private func sessionQuarantine(root: URL, sessionID: UUID) -> URL {
        sessionDirectory(root: root, sessionID: sessionID)
            .appendingPathComponent("quarantine", isDirectory: true)
    }

    private func globalQuarantine(root: URL) -> URL {
        storeRoot(root).appendingPathComponent("quarantine", isDirectory: true)
    }

    private func tombstoneURL(root: URL, sessionID: UUID) -> URL {
        storeRoot(root)
            .appendingPathComponent("deletion-tombstones", isDirectory: true)
            .appendingPathComponent(
                "\(RecognitionStudyCanonicalUUID(sessionID).rawValue).json"
            )
    }

    private func appendWhitespace(to url: URL) throws {
        var data = try Data(contentsOf: url)
        data.append(0x20)
        try data.write(to: url)
    }

    private func assertStoreError<Value>(
        _ expected: RecognitionStudyLocalCaptureStoreError,
        operation: () async throws -> Value
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected).")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyLocalCaptureStoreError,
                expected
            )
        }
    }

    private func assertStoreQuota<Value>(
        field: String,
        operation: () async throws -> Value
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected quota failure for \(field).")
        } catch {
            guard case .quotaExceeded(let actualField, _, _) =
                    error as? RecognitionStudyLocalCaptureStoreError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(actualField, field)
        }
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

private enum StoreInjectedFailure: Error, Equatable {
    case stop
}

private final class StoreTestControl: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProtectedDataAvailable = true
    private var storedFaultPoint:
        RecognitionStudyLocalCaptureStoreFaultPoint?
    private var storedPolicyRequests:
        [RecognitionStudyLocalCaptureStorePolicyRequest] = []

    var protectedDataAvailable: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedProtectedDataAvailable
        }
        set {
            lock.lock()
            storedProtectedDataAvailable = newValue
            lock.unlock()
        }
    }

    var faultPoint: RecognitionStudyLocalCaptureStoreFaultPoint? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedFaultPoint
        }
        set {
            lock.lock()
            storedFaultPoint = newValue
            lock.unlock()
        }
    }

    var policyRequests: [RecognitionStudyLocalCaptureStorePolicyRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedPolicyRequests
    }

    func record(_ request: RecognitionStudyLocalCaptureStorePolicyRequest) {
        lock.lock()
        storedPolicyRequests.append(request)
        lock.unlock()
    }

    func inject(
        _ point: RecognitionStudyLocalCaptureStoreFaultPoint
    ) throws {
        lock.lock()
        let shouldFail = storedFaultPoint == point
        lock.unlock()
        if shouldFail {
            throw StoreInjectedFailure.stop
        }
    }
}
