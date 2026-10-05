import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyPendingCaptureUploadStoreTests: XCTestCase {
    func testExactPreparedUploadRoundTripsWithProtectedNoBackupStorage() async throws {
        let root = try temporaryRoot()
        let control = PendingStoreTestControl()
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root,
            hooks: control.hooks
        )
        let fixture = try makeFixture(x: 1)

        let stored = try await store.enqueue(
            fixture.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100
        )
        let retry = try await store.enqueue(
            fixture.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_999
        )
        XCTAssertEqual(stored, fixture.upload)
        XCTAssertEqual(retry, fixture.upload)
        let pending = try await store.pendingUploads()
        XCTAssertEqual(pending, [fixture.upload])

        let captureDirectory = pendingDirectory(
            root: root,
            captureID: fixture.upload.captureAuthorizationID.rawValue
        )
        XCTAssertEqual(
            try Set(
                FileManager.default.contentsOfDirectory(
                    atPath: captureDirectory.path
                )
            ),
            [
                "commit.json",
                "envelope.json",
                "trajectory.json",
                "upload-request.json"
            ]
        )
        let requestURL = captureDirectory.appendingPathComponent(
            "upload-request.json"
        )
        XCTAssertEqual(
            try Data(contentsOf: requestURL),
            fixture.upload.canonicalRequestBody
        )
        XCTAssertFalse(
            String(
                decoding: fixture.upload.canonicalRequestBody,
                as: UTF8.self
            ).contains("access-token")
        )
        XCTAssertTrue(
            control.policyRequests.contains { request in
                guard case .completeFileProtection(let url) = request else {
                    return false
                }
                return url.lastPathComponent == "upload-request.json"
            }
        )
        XCTAssertTrue(
            control.policyRequests.contains { request in
                guard case .excludeFromBackup(let url) = request else {
                    return false
                }
                return url.lastPathComponent == "upload-request.json"
            }
        )
        XCTAssertEqual(
            try requestURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup,
            true
        )

        let reopened = try await RecognitionStudyPendingCaptureUploadStore
            .open(rootDirectory: root)
        let reopenedPending = try await reopened.pendingUploads()
        XCTAssertEqual(reopenedPending, [fixture.upload])
    }

    func testSameTicketWithDifferentImmutableBytesConflicts() async throws {
        let root = try temporaryRoot()
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root
        )
        let original = try makeFixture(x: 1)
        let changed = try makeFixture(x: 2)
        _ = try await store.enqueue(
            original.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100
        )

        do {
            _ = try await store.enqueue(
                changed.upload,
                enqueuedAtUnixMilliseconds: 1_800_000_200_200
            )
            XCTFail("One-use ticket bytes must be immutable.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyPendingCaptureUploadStoreError,
                .captureConflict(
                    original.upload.captureAuthorizationID.rawValue
                )
            )
        }
        let pending = try await store.pendingUploads()
        XCTAssertEqual(pending, [original.upload])
    }

    func testCommittedStageRecoversAfterPromotionCrash() async throws {
        let root = try temporaryRoot()
        let control = PendingStoreTestControl()
        control.fault = .afterCommitSynchronizationBeforePromotion
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root,
            hooks: control.hooks
        )
        let fixture = try makeFixture(x: 3)

        do {
            _ = try await store.enqueue(
                fixture.upload,
                enqueuedAtUnixMilliseconds: 1_800_000_200_100
            )
            XCTFail("Injected crash boundary should throw.")
        } catch {
            XCTAssertEqual((error as NSError).domain, "PendingStoreTestFault")
        }

        let reopened = try await RecognitionStudyPendingCaptureUploadStore
            .open(rootDirectory: root)
        let pending = try await reopened.pendingUploads()
        XCTAssertEqual(pending, [fixture.upload])
    }

    func testFullySynchronizedPayloadRecoversBeforePromotion() async throws {
        let root = try temporaryRoot()
        let control = PendingStoreTestControl()
        control.fault = .afterPayloadSynchronizationBeforePromotion
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root,
            hooks: control.hooks
        )
        let fixture = try makeFixture(x: 3.5)

        do {
            _ = try await store.enqueue(
                fixture.upload,
                enqueuedAtUnixMilliseconds: 1_800_000_200_100
            )
            XCTFail("Injected payload crash boundary should throw.")
        } catch {
            XCTAssertEqual((error as NSError).domain, "PendingStoreTestFault")
        }

        let reopened = try await RecognitionStudyPendingCaptureUploadStore
            .open(rootDirectory: root)
        let pending = try await reopened.pendingUploads()
        XCTAssertEqual(pending, [fixture.upload])
    }

    func testReceiptBoundAcknowledgementIsCrashSafeAndPurgesRetry() async throws {
        let root = try temporaryRoot()
        let control = PendingStoreTestControl()
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root,
            hooks: control.hooks
        )
        let fixture = try makeFixture(x: 4)
        _ = try await store.enqueue(
            fixture.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100
        )
        let receipt = try makeReceipt(fixture: fixture)
        control.fault = .afterAcknowledgedMoveBeforeRemoval

        do {
            try await store.removeAcknowledged(by: receipt)
            XCTFail("Injected acknowledgement crash boundary should throw.")
        } catch {
            XCTAssertEqual((error as NSError).domain, "PendingStoreTestFault")
        }

        let reopened = try await RecognitionStudyPendingCaptureUploadStore
            .open(rootDirectory: root)
        let pending = try await reopened.pendingUploads()
        XCTAssertTrue(pending.isEmpty)

        do {
            try await reopened.removeAcknowledged(by: receipt)
            XCTFail("An acknowledged upload is no longer pending.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyPendingCaptureUploadStoreError,
                .captureNotFound(
                    fixture.upload.captureAuthorizationID.rawValue
                )
            )
        }
    }

    func testCorruptPendingBytesFailClosedWithoutSilentUpload() async throws {
        let root = try temporaryRoot()
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root
        )
        let fixture = try makeFixture(x: 5)
        _ = try await store.enqueue(
            fixture.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100
        )
        let requestURL = pendingDirectory(
            root: root,
            captureID: fixture.upload.captureAuthorizationID.rawValue
        ).appendingPathComponent("upload-request.json")
        try (Data([UInt8(ascii: " ")]) + fixture.upload.canonicalRequestBody)
            .write(to: requestURL, options: .atomic)

        do {
            _ = try await store.pendingUploads()
            XCTFail("Corrupt persisted bytes must never be returned for upload.")
        } catch {
            guard case .corruptArtifact =
                    error as? RecognitionStudyPendingCaptureUploadStoreError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestURL.path))

        // Opening remains possible so a withdrawal/account-deletion flow can
        // purge even bytes that are too corrupt to upload.
        let reopened = try await RecognitionStudyPendingCaptureUploadStore
            .open(rootDirectory: root)
        try await reopened.purgeAllPendingAndQuarantinedData()
        let pending = try await reopened.pendingUploads()
        XCTAssertTrue(pending.isEmpty)
    }

    func testProtectedDataAndQuotaFailuresOccurBeforeCommit() async throws {
        let unavailable = PendingStoreTestControl()
        unavailable.protectedDataAvailable = false
        do {
            _ = try await RecognitionStudyPendingCaptureUploadStore.open(
                rootDirectory: temporaryRoot(),
                hooks: unavailable.hooks
            )
            XCTFail("Protected data must be available before opening.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyPendingCaptureUploadStoreError,
                .protectedDataUnavailable
            )
        }

        let root = try temporaryRoot()
        let quotas = try RecognitionStudyPendingCaptureUploadStoreQuotas(
            maximumPendingCount: 1,
            maximumStoreByteCount: 1
        )
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root,
            quotas: quotas
        )
        let fixture = try makeFixture(x: 6)
        do {
            _ = try await store.enqueue(
                fixture.upload,
                enqueuedAtUnixMilliseconds: 1_800_000_200_100
            )
            XCTFail("Store-byte quota must fail before commit.")
        } catch {
            guard case .quotaExceeded(let field, _, _) =
                    error as? RecognitionStudyPendingCaptureUploadStoreError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(field, "storeByteCount")
        }
        let pending = try await store.pendingUploads()
        XCTAssertTrue(pending.isEmpty)
    }

    func testWithdrawalBarrierPurgesRawQueueSurvivesRestartAndBlocksUploads()
        async throws
    {
        let root = try temporaryRoot()
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root
        )
        let fixture = try makeFixture(x: 7)
        _ = try await store.enqueue(
            fixture.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100
        )
        let consentRecordID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")
        )
        let clientRequestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000004")
        )

        let intent = try await store.registerWithdrawalBarrierAndPurge(
            consentRecordID: consentRecordID,
            clientRequestID: clientRequestID
        )

        XCTAssertEqual(intent.consentRecordID.uuid, consentRecordID)
        XCTAssertEqual(intent.clientRequestID.uuid, clientRequestID)
        let stateAfterWithdrawal = try await store.withdrawalBarrierState()
        XCTAssertEqual(stateAfterWithdrawal, .pending(intent))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: pendingRootDirectory(root: root).path
            ).isEmpty
        )
        do {
            _ = try await store.pendingUploads()
            XCTFail("The withdrawal barrier must prevent reading upload work.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyPendingCaptureUploadStoreError,
                .withdrawalBarrierActive
            )
        }

        let reopened = try await RecognitionStudyPendingCaptureUploadStore
            .open(rootDirectory: root)
        let reopenedPendingState = try await reopened.withdrawalBarrierState()
        XCTAssertEqual(reopenedPendingState, .pending(intent))
        do {
            _ = try await reopened.enqueue(
                fixture.upload,
                enqueuedAtUnixMilliseconds: 1_800_000_200_200
            )
            XCTFail("Withdrawal must remain fail-closed after restart.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyPendingCaptureUploadStoreError,
                .withdrawalBarrierActive
            )
        }
    }

    func testWithdrawalAcknowledgementIsBoundDurableAndIdempotent()
        async throws
    {
        let root = try temporaryRoot()
        let store = try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root
        )
        let consentRecordID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")
        )
        let clientRequestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000004")
        )
        let intent = try await store.registerWithdrawalBarrierAndPurge(
            consentRecordID: consentRecordID,
            clientRequestID: clientRequestID
        )
        let response = try withdrawnConsentResponse()

        try await store.markWithdrawalAcknowledged(response, for: intent)
        try await store.markWithdrawalAcknowledged(response, for: intent)
        let acknowledgedState = try await store.withdrawalBarrierState()
        XCTAssertEqual(acknowledgedState, .acknowledged(intent, response))

        let reopened = try await RecognitionStudyPendingCaptureUploadStore
            .open(rootDirectory: root)
        let reopenedAcknowledgedState =
            try await reopened.withdrawalBarrierState()
        XCTAssertEqual(
            reopenedAcknowledgedState,
            .acknowledged(intent, response)
        )
        do {
            _ = try await reopened.registerWithdrawalBarrierAndPurge(
                consentRecordID: consentRecordID,
                clientRequestID: UUID()
            )
            XCTFail("A new idempotency identity must not replace the barrier.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyPendingCaptureUploadStoreError,
                .withdrawalIntentConflict
            )
        }
    }

    private struct Fixture {
        let upload: RecognitionStudyPreparedCaptureUpload
        let envelope: RecognitionStudyAuthorizedCaptureEnvelope
        let packet: ChordInkCanonicalTrajectoryPacket
    }

    private func makeFixture(x: Double) throws -> Fixture {
        let grant = try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
            Data(TestGrant.validArtifact.utf8)
        )
        let publicKey = try XCTUnwrap(
            Data(base64Encoded: TestGrant.publicKeyBase64)
        )
        let verified = try RecognitionStudyVerifiedCaptureGrant.verify(
            grant,
            trustedPublicKeysByID: [TestGrant.signingKeyID: publicKey],
            validationUnixSeconds: TestGrant.validationTime,
            actualBundleIdentifier: TestGrant.bundleIdentifier,
            actualBuildNumber: "51"
        )
        let ticket = verified.payload.captureTickets[0]
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [InkPoint(x: x, y: 2, timeOffset: 0.25)],
                creationTimeOffset: 0
            )
        ])
        let envelope = try RecognitionStudyAuthorizedCaptureEnvelope(
            verifiedGrant: verified,
            ticket: ticket,
            clientAppContext: RecognitionStudyClientAppContext(
                appVersion: "1.0",
                buildNumber: "51",
                operatingSystemMajorVersion: 26,
                operatingSystemMinorVersion: 0
            ),
            clientObservedSurface: RecognitionStudyPresentedSurface(
                presentedChartStyle: .simpleChordSheet,
                clientObservedOrientation: .portrait,
                canvasWidth: 768,
                canvasHeight: 1024,
                presentedPaceInstruction: .natural,
                presentedSizeInstruction: .normal,
                presentedConstructionInstruction: .rootFirst
            ),
            clientCapturedAtUnixMilliseconds: 1_800_000_200_000,
            packet: packet
        )
        return Fixture(
            upload: try RecognitionStudyPreparedCaptureUpload(
                verifiedGrant: verified,
                ticket: ticket,
                envelope: envelope,
                packet: packet
            ),
            envelope: envelope,
            packet: packet
        )
    }

    private func makeReceipt(
        fixture: Fixture
    ) throws -> RecognitionStudyCaptureReceipt {
        let packetData = try fixture.packet.canonicalData()
        let text = #"{"accepted":true,"canonicalPacketByteCount":\#(packetData.count),"canonicalPacketSHA256":"\#(RecognitionStudySHA256(digesting: packetData).rawValue)","captureAuthorizationID":"\#(fixture.upload.captureAuthorizationID.rawValue)","envelopeSHA256":"\#(RecognitionStudySHA256(digesting: try fixture.envelope.canonicalData()).rawValue)","grantCompleted":false,"receiptID":"77777777-7777-4777-8777-777777777777","receivedAtUnixMilliseconds":1800000201000,"replayed":false,"schemaVersion":"recognition-study-capture-receipt-v1"}"#
        return try RecognitionStudyCaptureReceipt.decodeCanonicalData(
            Data(text.utf8)
        )
    }

    private func withdrawnConsentResponse() throws
        -> RecognitionStudyConsentResponse
    {
        let text = #"{"consent":{"acceptedAtUnixMilliseconds":1800000000000,"consentLedgerEpoch":9,"consentLedgerVersion":"consent-ledger-v1","consentRecordID":"10000000-0000-4000-8000-000000000003","consentRecordSHA256":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd","consentTextVersion":"consent-text-v1","dataUsePolicyVersion":"raw-stroke-research-v1","privacyNoticeVersion":"privacy-notice-v1","rawStrokeDonationAuthorized":true,"retentionPolicyVersion":"retention-12-months-v1","schemaVersion":"recognition-study-consent-record-summary-v1","scope":"chord-recognition-research-v1","status":"withdrawn","withdrawnAtUnixMilliseconds":1800000100000},"currentPolicy":null,"replayed":false,"schemaVersion":"recognition-study-consent-response-v1","status":"withdrawn"}"#
        return try RecognitionStudyConsentResponse.decodeCanonicalData(
            Data(text.utf8)
        )
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-upload-tests-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func pendingDirectory(root: URL, captureID: String) -> URL {
        pendingRootDirectory(root: root)
            .appendingPathComponent(captureID, isDirectory: true)
    }

    private func pendingRootDirectory(root: URL) -> URL {
        root.appendingPathComponent(
            RecognitionStudyPendingCaptureUploadStore.storeDirectoryName,
            isDirectory: true
        )
        .appendingPathComponent("pending", isDirectory: true)
    }
}

private final class PendingStoreTestControl: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProtectedDataAvailable = true
    private var storedFault:
        RecognitionStudyPendingCaptureUploadStoreFaultPoint?
    private var storedPolicyRequests:
        [RecognitionStudyPendingCaptureUploadStorePolicyRequest] = []

    var protectedDataAvailable: Bool {
        get { withLock { storedProtectedDataAvailable } }
        set { withLock { storedProtectedDataAvailable = newValue } }
    }

    var fault: RecognitionStudyPendingCaptureUploadStoreFaultPoint? {
        get { withLock { storedFault } }
        set { withLock { storedFault = newValue } }
    }

    var policyRequests:
        [RecognitionStudyPendingCaptureUploadStorePolicyRequest] {
        withLock { storedPolicyRequests }
    }

    var hooks: RecognitionStudyPendingCaptureUploadStoreHooks {
        RecognitionStudyPendingCaptureUploadStoreHooks(
            isProtectedDataAvailable: { [weak self] in
                self?.protectedDataAvailable ?? false
            },
            observePolicyRequest: { [weak self] request in
                self?.withLock { self?.storedPolicyRequests.append(request) }
            },
            injectFault: { [weak self] point in
                guard let self else { return }
                let shouldThrow = self.withLock { () -> Bool in
                    guard self.storedFault == point else { return false }
                    self.storedFault = nil
                    return true
                }
                if shouldThrow {
                    throw NSError(
                        domain: "PendingStoreTestFault",
                        code: 1
                    )
                }
            }
        )
    }

    @discardableResult
    private func withLock<Value>(_ operation: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
