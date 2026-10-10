import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyCaptureTransportModelsTests: XCTestCase {
    func testGrantRequestIsCanonicalAndContainsNoAuthorityClaim() throws {
        let request = try RecognitionStudyCaptureGrantRequest(
            clientRequestID: try XCTUnwrap(
                UUID(uuidString: "66666666-6666-4666-8666-666666666666")
            )
        )
        let data = try request.canonicalData()

        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"{"clientRequestID":"66666666-6666-4666-8666-666666666666","schemaVersion":"recognition-study-capture-grant-request-v1"}"#
        )
        XCTAssertLessThanOrEqual(
            data.count,
            RecognitionStudyCaptureGrantRequest.maximumCanonicalJSONByteCount
        )
    }

    func testUploadRequestMatchesSharedCrossLanguageGoldenExactly() throws {
        let fixture = try makeFixture()
        let request = try RecognitionStudyCaptureUploadRequest(
            verifiedGrant: fixture.verifiedGrant,
            ticket: fixture.ticket,
            envelope: fixture.envelope,
            packet: fixture.packet
        )
        let canonical = try request.canonicalData()

        XCTAssertEqual(
            canonical,
            try canonicalFixtureData(
                named: "authorized_capture_upload_request_v1.json"
            )
        )
        XCTAssertEqual(canonical.count, 4_288)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: canonical)
                as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            [
                "canonicalPacketBase64",
                "envelope",
                "schemaVersion",
                "signedGrant"
            ]
        )
    }

    func testPreparedUploadRestoresOnlyTheExactBoundArtifacts() throws {
        let fixture = try makeFixture()
        let prepared = try RecognitionStudyPreparedCaptureUpload(
            verifiedGrant: fixture.verifiedGrant,
            ticket: fixture.ticket,
            envelope: fixture.envelope,
            packet: fixture.packet
        )
        let restored = try RecognitionStudyPreparedCaptureUpload(
            restoringCanonicalRequestBody: prepared.canonicalRequestBody,
            canonicalEnvelopeData: fixture.envelope.canonicalData(),
            canonicalPacketData: fixture.packet.canonicalData()
        )

        XCTAssertEqual(restored, prepared)
        XCTAssertEqual(
            restored.captureAuthorizationID,
            fixture.ticket.captureAuthorizationID
        )

        let differentPacket = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(points: [InkPoint(x: 99, y: 2, timeOffset: 0.25)])
        ])
        XCTAssertThrowsError(
            try RecognitionStudyPreparedCaptureUpload(
                restoringCanonicalRequestBody: prepared.canonicalRequestBody,
                canonicalEnvelopeData: fixture.envelope.canonicalData(),
                canonicalPacketData: differentPacket.canonicalData()
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureTransportContractError,
                .uploadRequestDoesNotMatchArtifacts
            )
        }

        XCTAssertThrowsError(
            try RecognitionStudyPreparedCaptureUpload(
                restoringCanonicalRequestBody:
                    Data([UInt8(ascii: " ")]) + prepared.canonicalRequestBody,
                canonicalEnvelopeData: fixture.envelope.canonicalData(),
                canonicalPacketData: fixture.packet.canonicalData()
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureTransportContractError,
                .invalidCanonicalUploadRequest
            )
        }
    }

    func testReceiptStrictlyDecodesAndBindsToCapture() throws {
        let fixture = try makeFixture()
        let envelopeSHA256 = RecognitionStudySHA256(
            digesting: try fixture.envelope.canonicalData()
        ).rawValue
        let packetData = try fixture.packet.canonicalData()
        let packetSHA256 = RecognitionStudySHA256(
            digesting: packetData
        ).rawValue
        let receiptText = #"{"accepted":true,"canonicalPacketByteCount":\#(packetData.count),"canonicalPacketSHA256":"\#(packetSHA256)","captureAuthorizationID":"44444444-4444-4444-8444-444444444444","envelopeSHA256":"\#(envelopeSHA256)","grantCompleted":false,"receiptID":"77777777-7777-4777-8777-777777777777","receivedAtUnixMilliseconds":1800000201000,"replayed":false,"schemaVersion":"recognition-study-capture-receipt-v1"}"#
        let data = Data(receiptText.utf8)
        let receipt = try RecognitionStudyCaptureReceipt.decodeCanonicalData(data)

        XCTAssertEqual(try receipt.canonicalData(), data)
        XCTAssertNoThrow(
            try receipt.validateBinding(
                envelope: fixture.envelope,
                packet: fixture.packet
            )
        )
        XCTAssertFalse(receipt.replayed)
        XCTAssertFalse(receipt.grantCompleted)
    }

    func testReceiptRejectsUnknownNoncanonicalFalseAndMismatchedValues() throws {
        let fixture = try makeFixture()
        let envelopeSHA256 = RecognitionStudySHA256(
            digesting: try fixture.envelope.canonicalData()
        ).rawValue
        let packetData = try fixture.packet.canonicalData()
        let packetSHA256 = RecognitionStudySHA256(
            digesting: packetData
        ).rawValue
        let canonical = #"{"accepted":true,"canonicalPacketByteCount":\#(packetData.count),"canonicalPacketSHA256":"\#(packetSHA256)","captureAuthorizationID":"44444444-4444-4444-8444-444444444444","envelopeSHA256":"\#(envelopeSHA256)","grantCompleted":true,"receiptID":"77777777-7777-4777-8777-777777777777","receivedAtUnixMilliseconds":1800000201000,"replayed":true,"schemaVersion":"recognition-study-capture-receipt-v1"}"#

        XCTAssertThrowsError(
            try RecognitionStudyCaptureReceipt.decodeCanonicalData(
                Data(" \(canonical)".utf8)
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyCaptureReceipt.decodeCanonicalData(
                Data((String(canonical.dropLast()) + ",\"unknown\":true}").utf8)
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyCaptureReceipt.decodeCanonicalData(
                Data(
                    canonical.replacingOccurrences(
                        of: "\"accepted\":true",
                        with: "\"accepted\":false"
                    ).utf8
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureTransportContractError,
                .invalidReceiptState
            )
        }

        let mismatched = canonical.replacingOccurrences(
            of: packetSHA256,
            with: String(repeating: "0", count: 64)
        )
        let receipt = try RecognitionStudyCaptureReceipt.decodeCanonicalData(
            Data(mismatched.utf8)
        )
        XCTAssertThrowsError(
            try receipt.validateBinding(
                envelope: fixture.envelope,
                packet: fixture.packet
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureTransportContractError,
                .receiptDoesNotMatchCapture
            )
        }
    }

    private struct Fixture {
        let verifiedGrant: RecognitionStudyVerifiedCaptureGrant
        let ticket: RecognitionStudyCaptureGrantPromptTicket
        let packet: ChordInkCanonicalTrajectoryPacket
        let envelope: RecognitionStudyAuthorizedCaptureEnvelope
    }

    private func makeFixture() throws -> Fixture {
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
                points: [InkPoint(x: 1, y: 2, timeOffset: 0.25)],
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
            verifiedGrant: verified,
            ticket: ticket,
            packet: packet,
            envelope: envelope
        )
    }

    private func canonicalFixtureData(named name: String) throws -> Data {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stored = try Data(
            contentsOf: projectRoot
                .appendingPathComponent("recognition_contract_fixtures")
                .appendingPathComponent(name)
        )
        XCTAssertEqual(stored.last, UInt8(ascii: "\n"))
        return stored.dropLast()
    }
}
