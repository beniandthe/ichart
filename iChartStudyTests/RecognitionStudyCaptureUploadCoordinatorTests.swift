import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyCaptureUploadCoordinatorTests: XCTestCase {
    func testNewCaptureIsDurableBeforeNetworkAndRemovedOnlyAfterReceipt()
        async throws
    {
        let store = try await makeStore()
        let fixture = try makeFixture(ticketOrdinal: 0, x: 1)
        let receipt = try makeReceipt(fixture: fixture, replayed: false)
        let uploader = RecognitionStudyCaptureUploaderStub(
            steps: [.success(receipt)],
            observeUpload: { upload in
                let pending = try await store.pendingUploads()
                XCTAssertEqual(pending, [upload])
            }
        )
        let coordinator = RecognitionStudyCaptureUploadCoordinator(
            store: store,
            uploader: uploader
        )

        let result = try await coordinator.enqueueAndFlush(
            fixture.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100,
            accessTokenProvider: { "first-access-token" }
        )

        XCTAssertEqual(result.acknowledgedReceipts, [receipt])
        XCTAssertEqual(result.remainingCaptureCount, 0)
        let pendingAfterReceipt = try await store.pendingUploads()
        XCTAssertTrue(pendingAfterReceipt.isEmpty)
        let attempts = await uploader.recordedAttempts()
        XCTAssertEqual(attempts.map(\.upload), [fixture.upload])
        XCTAssertEqual(attempts.map(\.accessToken), ["first-access-token"])
    }

    func testFailedAttemptPreservesExactBytesAndRetryUsesFreshToken()
        async throws
    {
        let store = try await makeStore()
        let fixture = try makeFixture(ticketOrdinal: 0, x: 2)
        let receipt = try makeReceipt(fixture: fixture, replayed: true)
        let uploader = RecognitionStudyCaptureUploaderStub(
            steps: [.failure, .success(receipt)]
        )
        let coordinator = RecognitionStudyCaptureUploadCoordinator(
            store: store,
            uploader: uploader
        )

        do {
            _ = try await coordinator.enqueueAndFlush(
                fixture.upload,
                enqueuedAtUnixMilliseconds: 1_800_000_200_100,
                accessTokenProvider: { "expired-access-token" }
            )
            XCTFail("The injected transport failure should surface.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyCaptureUploaderStubError,
                .unavailable
            )
        }
        let pendingAfterFailure = try await store.pendingUploads()
        XCTAssertEqual(pendingAfterFailure, [fixture.upload])

        let result = try await coordinator.flushPending(
            accessTokenProvider: { "fresh-access-token" }
        )

        XCTAssertEqual(result.acknowledgedReceipts, [receipt])
        XCTAssertEqual(result.remainingCaptureCount, 0)
        let attempts = await uploader.recordedAttempts()
        XCTAssertEqual(attempts.map(\.upload), [fixture.upload, fixture.upload])
        XCTAssertEqual(
            attempts.map(\.upload.canonicalRequestBody),
            [
                fixture.upload.canonicalRequestBody,
                fixture.upload.canonicalRequestBody
            ]
        )
        XCTAssertEqual(
            attempts.map(\.accessToken),
            ["expired-access-token", "fresh-access-token"]
        )
    }

    func testFlushStopsAtFirstFailureAndKeepsLaterCapturesPending()
        async throws
    {
        let store = try await makeStore()
        let first = try makeFixture(ticketOrdinal: 0, x: 3)
        let second = try makeFixture(ticketOrdinal: 1, x: 4)
        _ = try await store.enqueue(
            second.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_200
        )
        _ = try await store.enqueue(
            first.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100
        )
        let firstReceipt = try makeReceipt(
            fixture: first,
            replayed: false
        )
        let uploader = RecognitionStudyCaptureUploaderStub(
            steps: [.success(firstReceipt), .failure]
        )
        let coordinator = RecognitionStudyCaptureUploadCoordinator(
            store: store,
            uploader: uploader
        )

        do {
            _ = try await coordinator.flushPending(
                accessTokenProvider: { "access-token" }
            )
            XCTFail("The second injected upload should fail.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyCaptureUploaderStubError,
                .unavailable
            )
        }

        let pendingAfterFailure = try await store.pendingUploads()
        XCTAssertEqual(pendingAfterFailure, [second.upload])
        let attempts = await uploader.recordedAttempts()
        XCTAssertEqual(
            attempts.map(\.upload.captureAuthorizationID),
            [
                first.upload.captureAuthorizationID,
                second.upload.captureAuthorizationID
            ]
        )
    }

    func testCancellationBeforeTokenLookupLeavesCapturePending()
        async throws
    {
        let store = try await makeStore()
        let fixture = try makeFixture(ticketOrdinal: 0, x: 5)
        _ = try await store.enqueue(
            fixture.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100
        )
        let uploader = RecognitionStudyCaptureUploaderStub(steps: [])
        let coordinator = RecognitionStudyCaptureUploadCoordinator(
            store: store,
            uploader: uploader
        )
        let task = Task {
            try await coordinator.flushPending(
                accessTokenProvider: { "must-not-be-used" }
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled flush should throw.")
        } catch is CancellationError {
            // Expected.
        }

        let pendingAfterCancellation = try await store.pendingUploads()
        let attempts = await uploader.recordedAttempts()
        XCTAssertEqual(pendingAfterCancellation, [fixture.upload])
        XCTAssertTrue(attempts.isEmpty)
    }

    func testWithdrawalPersistsBarrierPurgesAndAcknowledgesWithFreshToken()
        async throws
    {
        let store = try await makeStore()
        let fixture = try makeFixture(ticketOrdinal: 0, x: 6)
        _ = try await store.enqueue(
            fixture.upload,
            enqueuedAtUnixMilliseconds: 1_800_000_200_100
        )
        let response = try withdrawnConsentResponse()
        let withdrawer = RecognitionStudyConsentWithdrawerStub(
            steps: [.success(response)],
            observeWithdrawal: { _, _ in
                guard case .pending =
                        try await store.withdrawalBarrierState() else {
                    return XCTFail(
                        "The barrier must exist before network access."
                    )
                }
                do {
                    _ = try await store.pendingUploads()
                    XCTFail("Withdrawal must block queued upload access.")
                } catch {
                    XCTAssertEqual(
                        error as?
                            RecognitionStudyPendingCaptureUploadStoreError,
                        .withdrawalBarrierActive
                    )
                }
            }
        )
        let coordinator = RecognitionStudyConsentWithdrawalCoordinator(
            store: store,
            consentWithdrawer: withdrawer
        )
        let consentRecordID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")
        )
        let clientRequestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000004")
        )

        let result = try await coordinator.requestWithdrawal(
            consentRecordID: consentRecordID,
            clientRequestID: clientRequestID,
            accessTokenProvider: { "withdrawal-access-token" }
        )

        XCTAssertEqual(result, response)
        let expectedIntent = try RecognitionStudyPendingConsentWithdrawal(
            clientRequestID: clientRequestID,
            consentRecordID: consentRecordID
        )
        let acknowledgedState = try await store.withdrawalBarrierState()
        XCTAssertEqual(
            acknowledgedState,
            .acknowledged(expectedIntent, response)
        )
        let replay = try await coordinator.requestWithdrawal(
            consentRecordID: consentRecordID,
            clientRequestID: clientRequestID,
            accessTokenProvider: {
                XCTFail("Acknowledged withdrawal must not request a token.")
                return "must-not-be-used"
            }
        )
        XCTAssertEqual(replay, response)
        let attempts = await withdrawer.recordedAttempts()
        XCTAssertEqual(attempts.map(\.accessToken), ["withdrawal-access-token"])
        XCTAssertEqual(attempts.map(\.clientRequestID), [clientRequestID])
    }

    func testFailedWithdrawalRemainsPendingAndResumeReusesIdentity()
        async throws
    {
        let store = try await makeStore()
        let response = try withdrawnConsentResponse()
        let withdrawer = RecognitionStudyConsentWithdrawerStub(
            steps: [.failure, .success(response)]
        )
        let coordinator = RecognitionStudyConsentWithdrawalCoordinator(
            store: store,
            consentWithdrawer: withdrawer
        )
        let consentRecordID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")
        )
        let clientRequestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000004")
        )

        do {
            _ = try await coordinator.requestWithdrawal(
                consentRecordID: consentRecordID,
                clientRequestID: clientRequestID,
                accessTokenProvider: { "expired-token" }
            )
            XCTFail("The injected network failure should surface.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyConsentWithdrawerStubError,
                .unavailable
            )
        }
        guard case .pending(let intent) =
                try await store.withdrawalBarrierState() else {
            return XCTFail("The failed server attempt must remain pending.")
        }

        let result = try await coordinator.resumeWithdrawal(
            accessTokenProvider: { "fresh-token" }
        )

        XCTAssertEqual(result, response)
        XCTAssertEqual(intent.clientRequestID.uuid, clientRequestID)
        let attempts = await withdrawer.recordedAttempts()
        XCTAssertEqual(
            attempts.map(\.clientRequestID),
            [clientRequestID, clientRequestID]
        )
        XCTAssertEqual(
            attempts.map(\.accessToken),
            ["expired-token", "fresh-token"]
        )
    }

    func testCancelledWithdrawalStillInstallsBarrierBeforeTokenLookup()
        async throws
    {
        let store = try await makeStore()
        let withdrawer = RecognitionStudyConsentWithdrawerStub(steps: [])
        let coordinator = RecognitionStudyConsentWithdrawalCoordinator(
            store: store,
            consentWithdrawer: withdrawer
        )
        let consentRecordID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")
        )
        let clientRequestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000004")
        )
        let task = Task {
            try await coordinator.requestWithdrawal(
                consentRecordID: consentRecordID,
                clientRequestID: clientRequestID,
                accessTokenProvider: { "must-not-be-used" }
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancellation should stop before token lookup.")
        } catch is CancellationError {
            // Expected after the local privacy boundary is durable.
        }

        guard case .pending(let intent) =
                try await store.withdrawalBarrierState() else {
            return XCTFail("Cancellation must not reopen uploads.")
        }
        XCTAssertEqual(intent.clientRequestID.uuid, clientRequestID)
        let attempts = await withdrawer.recordedAttempts()
        XCTAssertTrue(attempts.isEmpty)
    }

    private struct Fixture {
        let upload: RecognitionStudyPreparedCaptureUpload
        let envelope: RecognitionStudyAuthorizedCaptureEnvelope
        let packet: ChordInkCanonicalTrajectoryPacket
    }

    private func makeStore()
        async throws -> RecognitionStudyPendingCaptureUploadStore
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "capture-upload-coordinator-tests-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return try await RecognitionStudyPendingCaptureUploadStore.open(
            rootDirectory: root
        )
    }

    private func makeFixture(
        ticketOrdinal: Int,
        x: Double
    ) throws -> Fixture {
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
        let ticket = verified.payload.captureTickets[ticketOrdinal]
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [InkPoint(x: x, y: 2, timeOffset: 0.25)],
                creationTimeOffset: 0
            )
        ])
        let chartStyle = try XCTUnwrap(
            RecognitionStudyPresentedChartStyle(
                rawValue: ticket.presentedChartStyle.rawValue
            )
        )
        let orientation = try XCTUnwrap(
            RecognitionStudyObservedOrientation(
                rawValue: ticket.requestedOrientation.rawValue
            )
        )
        let pace = try XCTUnwrap(
            RecognitionStudyPresentedPaceInstruction(
                rawValue: ticket.presentedPace.rawValue
            )
        )
        let size = try XCTUnwrap(
            RecognitionStudyPresentedSizeInstruction(
                rawValue: ticket.presentedSize.rawValue
            )
        )
        let construction = try XCTUnwrap(
            RecognitionStudyPresentedConstructionInstruction(
                rawValue: ticket.presentedConstruction.rawValue
            )
        )
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
                presentedChartStyle: chartStyle,
                clientObservedOrientation: orientation,
                canvasWidth: 768,
                canvasHeight: 1024,
                presentedPaceInstruction: pace,
                presentedSizeInstruction: size,
                presentedConstructionInstruction: construction
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
        fixture: Fixture,
        replayed: Bool
    ) throws -> RecognitionStudyCaptureReceipt {
        let packetData = try fixture.packet.canonicalData()
        let receiptID = replayed
            ? "88888888-8888-4888-8888-888888888888"
            : "77777777-7777-4777-8777-777777777777"
        let text = #"{"accepted":true,"canonicalPacketByteCount":\#(packetData.count),"canonicalPacketSHA256":"\#(RecognitionStudySHA256(digesting: packetData).rawValue)","captureAuthorizationID":"\#(fixture.upload.captureAuthorizationID.rawValue)","envelopeSHA256":"\#(RecognitionStudySHA256(digesting: try fixture.envelope.canonicalData()).rawValue)","grantCompleted":false,"receiptID":"\#(receiptID)","receivedAtUnixMilliseconds":1800000201000,"replayed":\#(replayed),"schemaVersion":"recognition-study-capture-receipt-v1"}"#
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
}

private enum RecognitionStudyCaptureUploaderStubError: Error, Equatable {
    case unavailable
}

private actor RecognitionStudyCaptureUploaderStub:
    RecognitionStudyPreparedCaptureUploading
{
    enum Step: Sendable {
        case success(RecognitionStudyCaptureReceipt)
        case failure
    }

    struct Attempt: Sendable {
        let upload: RecognitionStudyPreparedCaptureUpload
        let accessToken: String
    }

    private var steps: [Step]
    private var attempts: [Attempt] = []
    private let observeUpload:
        @Sendable (RecognitionStudyPreparedCaptureUpload) async throws -> Void

    init(
        steps: [Step],
        observeUpload: @escaping @Sendable (
            RecognitionStudyPreparedCaptureUpload
        ) async throws -> Void = { _ in }
    ) {
        self.steps = steps
        self.observeUpload = observeUpload
    }

    func uploadPreparedCapture(
        _ preparedUpload: RecognitionStudyPreparedCaptureUpload,
        accessToken: String
    ) async throws -> RecognitionStudyCaptureReceipt {
        attempts.append(
            Attempt(upload: preparedUpload, accessToken: accessToken)
        )
        try await observeUpload(preparedUpload)
        guard !steps.isEmpty else {
            throw RecognitionStudyCaptureUploaderStubError.unavailable
        }
        switch steps.removeFirst() {
        case .success(let receipt):
            return receipt
        case .failure:
            throw RecognitionStudyCaptureUploaderStubError.unavailable
        }
    }

    func recordedAttempts() -> [Attempt] {
        attempts
    }
}

private enum RecognitionStudyConsentWithdrawerStubError: Error, Equatable {
    case unavailable
}

private actor RecognitionStudyConsentWithdrawerStub:
    RecognitionStudyConsentWithdrawing
{
    enum Step: Sendable {
        case success(RecognitionStudyConsentResponse)
        case failure
    }

    struct Attempt: Sendable {
        let consentRecordID: UUID
        let clientRequestID: UUID
        let accessToken: String
    }

    private var steps: [Step]
    private var attempts: [Attempt] = []
    private let observeWithdrawal:
        @Sendable (UUID, UUID) async throws -> Void

    init(
        steps: [Step],
        observeWithdrawal: @escaping @Sendable (
            UUID,
            UUID
        ) async throws -> Void = { _, _ in }
    ) {
        self.steps = steps
        self.observeWithdrawal = observeWithdrawal
    }

    func withdraw(
        consentRecordID: UUID,
        clientRequestID: UUID,
        accessToken: String
    ) async throws -> RecognitionStudyConsentResponse {
        attempts.append(
            Attempt(
                consentRecordID: consentRecordID,
                clientRequestID: clientRequestID,
                accessToken: accessToken
            )
        )
        try await observeWithdrawal(consentRecordID, clientRequestID)
        guard !steps.isEmpty else {
            throw RecognitionStudyConsentWithdrawerStubError.unavailable
        }
        switch steps.removeFirst() {
        case .success(let response):
            return response
        case .failure:
            throw RecognitionStudyConsentWithdrawerStubError.unavailable
        }
    }

    func recordedAttempts() -> [Attempt] {
        attempts
    }
}
