import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyAuthorizedCaptureModelsTests: XCTestCase {
    func testCanonicalEnvelopeBindsExactVerifiedGrantTicketBuildSurfaceAndPacket() throws {
        let fixture = try makeFixture()
        let envelope = try makeEnvelope(fixture: fixture)
        let data = try envelope.canonicalData()
        let decoded = try RecognitionStudyAuthorizedCaptureEnvelope
            .decodeCanonicalData(data)

        XCTAssertEqual(decoded, envelope)
        XCTAssertNoThrow(
            try decoded.validateBindings(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                packet: fixture.packet
            )
        )
        XCTAssertEqual(
            decoded.artifactKind,
            .externallyAuthorizedTrajectoryV1
        )
        XCTAssertEqual(
            decoded.grantAuthorizationID,
            fixture.verifiedGrant.payload.authorizationID
        )
        XCTAssertEqual(
            decoded.serviceSessionID,
            fixture.verifiedGrant.payload.serviceSessionID
        )
        XCTAssertEqual(
            decoded.captureAuthorizationID,
            fixture.ticket.captureAuthorizationID
        )
        XCTAssertEqual(decoded.ticketOrdinal, fixture.ticket.ordinal)
        XCTAssertEqual(
            decoded.signedGrantSHA256,
            fixture.verifiedGrant.signedGrantSHA256
        )

        let object = try jsonObject(data)
        XCTAssertEqual(
            Set(object.keys),
            [
                "artifactKind",
                "captureAuthorizationID",
                "clientAppContext",
                "clientCapturedAtUnixMilliseconds",
                "clientObservedSurface",
                "grantAuthorizationID",
                "schemaVersion",
                "serviceSessionID",
                "signedGrantSHA256",
                "ticketOrdinal",
                "trajectoryDescriptor"
            ]
        )
    }

    func testRejectsWrongTicketDigestSurfaceAndPacketBindings() throws {
        let fixture = try makeFixture()
        let envelope = try makeEnvelope(fixture: fixture)
        let otherTicket = fixture.verifiedGrant.payload.captureTickets[1]

        XCTAssertThrowsError(
            try envelope.validateBindings(
                verifiedGrant: fixture.verifiedGrant,
                ticket: otherTicket,
                packet: fixture.packet
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyAuthorizedCaptureContractError,
                .ticketNotInVerifiedGrant
            )
        }

        let otherPacket = try packet(x: 99)
        XCTAssertThrowsError(
            try envelope.validateBindings(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                packet: otherPacket
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyAuthorizedCaptureContractError,
                .trajectoryDoesNotMatchPacket
            )
        }

        let wrongSurface = try RecognitionStudyPresentedSurface(
            presentedChartStyle: .simpleChordSheet,
            clientObservedOrientation: .landscape,
            canvasWidth: 1024,
            canvasHeight: 768,
            presentedPaceInstruction: .natural,
            presentedSizeInstruction: .normal,
            presentedConstructionInstruction: .rootFirst
        )
        XCTAssertThrowsError(
            try RecognitionStudyAuthorizedCaptureEnvelope(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                clientAppContext: fixture.clientContext,
                clientObservedSurface: wrongSurface,
                clientCapturedAtUnixMilliseconds: fixture.captureTime,
                packet: fixture.packet
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyAuthorizedCaptureContractError,
                .observedSurfaceDoesNotMatchTicket
            )
        }

        let digestTampered = String(
            decoding: try envelope.canonicalData(),
            as: UTF8.self
        ).replacingOccurrences(
            of: fixture.verifiedGrant.signedGrantSHA256.rawValue,
            with: String(repeating: "0", count: 64)
        )
        let decodedTampered = try RecognitionStudyAuthorizedCaptureEnvelope
            .decodeCanonicalData(Data(digestTampered.utf8))
        XCTAssertThrowsError(
            try decodedTampered.validateBindings(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                packet: fixture.packet
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyAuthorizedCaptureContractError,
                .signedGrantDigestMismatch
            )
        }
    }

    func testVerificationAndEnvelopeRejectWrongBundleAndBuild() throws {
        let grant = try signedGrant()
        let key = try publicKey()

        XCTAssertThrowsError(
            try RecognitionStudyVerifiedCaptureGrant.verify(
                grant,
                trustedPublicKeysByID: [TestGrant.signingKeyID: key],
                validationUnixSeconds: TestGrant.validationTime,
                actualBundleIdentifier: "com.ichart.app",
                actualBuildNumber: "51"
            )
        ) { error in
            guard case .fixedValueMismatch(let field, _, _) =
                    error as? RecognitionStudyAuthorizedCaptureContractError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(field, "actualBundleIdentifier")
        }

        XCTAssertThrowsError(
            try RecognitionStudyVerifiedCaptureGrant.verify(
                grant,
                trustedPublicKeysByID: [TestGrant.signingKeyID: key],
                validationUnixSeconds: TestGrant.validationTime,
                actualBundleIdentifier: TestGrant.bundleIdentifier,
                actualBuildNumber: "50"
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyAuthorizedCaptureContractError,
                .buildBelowGrantMinimum(actual: 50, minimum: 51)
            )
        }

        for invalidBuild in ["051", "51.0", "9007199254740992"] {
            XCTAssertThrowsError(
                try RecognitionStudyVerifiedCaptureGrant.verify(
                    grant,
                    trustedPublicKeysByID: [TestGrant.signingKeyID: key],
                    validationUnixSeconds: TestGrant.validationTime,
                    actualBundleIdentifier: TestGrant.bundleIdentifier,
                    actualBuildNumber: invalidBuild
                )
            )
        }

        let fixture = try makeFixture()
        let wrongContext = try RecognitionStudyClientAppContext(
            appVersion: "1.0",
            buildNumber: "52",
            operatingSystemMajorVersion: 26,
            operatingSystemMinorVersion: 0
        )
        XCTAssertThrowsError(
            try RecognitionStudyAuthorizedCaptureEnvelope(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                clientAppContext: wrongContext,
                clientObservedSurface: fixture.surface,
                clientCapturedAtUnixMilliseconds: fixture.captureTime,
                packet: fixture.packet
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyAuthorizedCaptureContractError,
                .clientContextDoesNotMatchVerifiedGrant
            )
        }
    }

    func testEnvelopeCaptureTimeMustFallInsideSignedGrantWindow() throws {
        let fixture = try makeFixture()
        for invalidCaptureTime: Int64 in [
            1_800_000_099_999,
            1_800_003_600_000
        ] {
            XCTAssertThrowsError(
                try RecognitionStudyAuthorizedCaptureEnvelope(
                    verifiedGrant: fixture.verifiedGrant,
                    ticket: fixture.ticket,
                    clientAppContext: fixture.clientContext,
                    clientObservedSurface: fixture.surface,
                    clientCapturedAtUnixMilliseconds: invalidCaptureTime,
                    packet: fixture.packet
                )
            ) { error in
                XCTAssertEqual(
                    error as? RecognitionStudyAuthorizedCaptureContractError,
                    .captureOutsideGrantValidityWindow
                )
            }
        }

        XCTAssertNoThrow(
            try RecognitionStudyAuthorizedCaptureEnvelope(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                clientAppContext: fixture.clientContext,
                clientObservedSurface: fixture.surface,
                clientCapturedAtUnixMilliseconds: 1_800_000_100_000,
                packet: fixture.packet
            )
        )
        XCTAssertNoThrow(
            try RecognitionStudyAuthorizedCaptureEnvelope(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                clientAppContext: fixture.clientContext,
                clientObservedSurface: fixture.surface,
                clientCapturedAtUnixMilliseconds: 1_800_003_599_999,
                packet: fixture.packet
            )
        )
    }

    func testStrictDecoderRejectsUnknownFieldsAndNoncanonicalBytes() throws {
        let fixture = try makeFixture()
        let envelope = try makeEnvelope(fixture: fixture)
        let canonical = String(
            decoding: try envelope.canonicalData(),
            as: UTF8.self
        )

        XCTAssertThrowsError(
            try RecognitionStudyAuthorizedCaptureEnvelope.decodeCanonicalData(
                Data(" \(canonical)".utf8)
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyAuthorizedCaptureEnvelope.decodeCanonicalData(
                Data((String(canonical.dropLast()) + ",\"unknown\":true}").utf8)
            )
        )

        let nestedUnknown = canonical.replacingOccurrences(
            of: "\"appVersion\":\"1.0\"",
            with: "\"appVersion\":\"1.0\",\"unknown\":true"
        )
        XCTAssertThrowsError(
            try RecognitionStudyAuthorizedCaptureEnvelope.decodeCanonicalData(
                Data(nestedUnknown.utf8)
            )
        )

        let unsafeTime = canonical.replacingOccurrences(
            of: String(fixture.captureTime),
            with: "9007199254740992"
        )
        XCTAssertThrowsError(
            try RecognitionStudyAuthorizedCaptureEnvelope.decodeCanonicalData(
                Data(unsafeTime.utf8)
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyAuthorizedCaptureContractError,
                .integerOutsideSafeJSONDomain(
                    field: "clientCapturedAtUnixMilliseconds"
                )
            )
        }
    }

    func testEnvelopeHasNoPromptIdentitySemanticsOrRecognitionKeys() throws {
        let envelope = try makeEnvelope(fixture: makeFixture())
        let data = try envelope.canonicalData()
        let object = try jsonObject(data)
        let keys = recursiveKeys(object).map { $0.lowercased() }

        for forbidden in [
            "prompt", "display", "label", "truth", "writer", "person",
            "account", "consent", "dataset", "split", "eligibility",
            "recognizer", "candidate", "confidence", "outcome"
        ] {
            XCTAssertFalse(
                keys.contains { $0.contains(forbidden) },
                "Authorized raw envelope contains forbidden key: \(forbidden)"
            )
        }
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("isolated-c-seven"))
        XCTAssertFalse(text.contains("\"C7\""))
        XCTAssertFalse(text.contains("writer-pilot-2026-01"))
        XCTAssertFalse(text.contains("33333333-3333-4333-8333-333333333333"))
    }

    func testSharedCrossLanguageGoldenMatchesSwiftCanonicalBytes() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(
            try fixture.packet.canonicalData(),
            try canonicalFixtureData(named: "ink_trajectory_packet_v1.json")
        )
        XCTAssertEqual(
            try makeEnvelope(fixture: fixture).canonicalData(),
            try canonicalFixtureData(named: "authorized_capture_envelope_v1.json")
        )
    }

    private struct Fixture {
        let verifiedGrant: RecognitionStudyVerifiedCaptureGrant
        let ticket: RecognitionStudyCaptureGrantPromptTicket
        let clientContext: RecognitionStudyClientAppContext
        let surface: RecognitionStudyPresentedSurface
        let packet: ChordInkCanonicalTrajectoryPacket
        let captureTime: Int64
    }

    private func makeFixture() throws -> Fixture {
        let grant = try signedGrant()
        let verified = try RecognitionStudyVerifiedCaptureGrant.verify(
            grant,
            trustedPublicKeysByID: [TestGrant.signingKeyID: try publicKey()],
            validationUnixSeconds: TestGrant.validationTime,
            actualBundleIdentifier: TestGrant.bundleIdentifier,
            actualBuildNumber: "51"
        )
        return try Fixture(
            verifiedGrant: verified,
            ticket: verified.payload.captureTickets[0],
            clientContext: RecognitionStudyClientAppContext(
                appVersion: "1.0",
                buildNumber: "51",
                operatingSystemMajorVersion: 26,
                operatingSystemMinorVersion: 0
            ),
            surface: RecognitionStudyPresentedSurface(
                presentedChartStyle: .simpleChordSheet,
                clientObservedOrientation: .portrait,
                canvasWidth: 768,
                canvasHeight: 1024,
                presentedPaceInstruction: .natural,
                presentedSizeInstruction: .normal,
                presentedConstructionInstruction: .rootFirst
            ),
            packet: packet(x: 1),
            captureTime: 1_800_000_200_000
        )
    }

    private func makeEnvelope(
        fixture: Fixture
    ) throws -> RecognitionStudyAuthorizedCaptureEnvelope {
        try RecognitionStudyAuthorizedCaptureEnvelope(
            verifiedGrant: fixture.verifiedGrant,
            ticket: fixture.ticket,
            clientAppContext: fixture.clientContext,
            clientObservedSurface: fixture.surface,
            clientCapturedAtUnixMilliseconds: fixture.captureTime,
            packet: fixture.packet
        )
    }

    private func packet(
        x: Double
    ) throws -> ChordInkCanonicalTrajectoryPacket {
        try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [InkPoint(x: x, y: 2, timeOffset: 0.25)],
                creationTimeOffset: 0
            )
        ])
    }

    private func signedGrant() throws -> RecognitionStudySignedCaptureGrant {
        try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
            Data(TestGrant.validArtifact.utf8)
        )
    }

    private func publicKey() throws -> Data {
        try XCTUnwrap(Data(base64Encoded: TestGrant.publicKeyBase64))
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func recursiveKeys(_ value: Any) -> [String] {
        if let object = value as? [String: Any] {
            return object.keys.flatMap { key in
                [key] + recursiveKeys(object[key] as Any)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(recursiveKeys)
        }
        return []
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

enum TestGrant {
    static let signingKeyID = "study-authority-test-v1"
    static let publicKeyBase64 =
        "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ="
    static let bundleIdentifier = "com.ichart.recognitionstudy"
    static let validationTime: Int64 = 1_800_000_100

    static let validArtifact = #"{"payload":{"artifactKind":"externally-authorized-session-grant-v1","authorizationEpoch":9,"authorizationID":"11111111-1111-4111-8111-111111111111","captureTickets":[{"captureAuthorizationID":"44444444-4444-4444-8444-444444444444","displayText":"C7","ordinal":0,"presentedChartStyle":"simple-chord-sheet","presentedConstruction":"root-first","presentedPace":"natural","presentedSize":"normal","promptID":"isolated-c-seven","promptKind":"isolated-chord","requestedOrientation":"portrait"},{"captureAuthorizationID":"55555555-5555-4555-8555-555555555555","displayText":"Bb7 | Eb7","ordinal":1,"presentedChartStyle":"rhythm-section-sheet","presentedConstruction":"mixed-or-retraced","presentedPace":"fast","presentedSize":"small","promptID":"row-b-flat-seven-e-flat-seven","promptKind":"realistic-row","requestedOrientation":"landscape"}],"clientRequirements":{"captureContractVersion":"recognition-study-authorized-capture-v1","expectedBundleIdentifier":"com.ichart.recognitionstudy","minimumBuildNumber":51},"collectionProtocolVersion":"writer-independent-capture-v2","consentBinding":{"consentLedgerEpoch":7,"consentLedgerVersion":"consent-ledger-v1","consentRecordID":"33333333-3333-4333-8333-333333333333","consentRecordSHA256":"abababababababababababababababababababababababababababababababab","consentTextVersion":"consent-text-v1","dataUsePolicyVersion":"raw-stroke-research-v1","privacyNoticeVersion":"privacy-notice-v1","rawStrokeDonationAuthorized":true,"retentionPolicyVersion":"retention-12-months-v1","schemaVersion":"recognition-study-consent-binding-v1","scope":"chord-recognition-research-v1"},"datasetVersion":"writer-pilot-2026-01","expectedCaptureCount":2,"expiresAtUnixSeconds":1800003600,"issuedAtUnixSeconds":1800000000,"notBeforeUnixSeconds":1800000100,"promptPlanVersion":"pilot-prompts-v1","schemaVersion":"recognition-study-capture-grant-v1","serviceSessionID":"22222222-2222-4222-8222-222222222222"},"schemaVersion":"recognition-study-signed-capture-grant-v1","signatureBase64":"Su0SaxTyWXz0O7bsxux5GkrKu9aBwJMg6I+GriIRHha7fuACjMzRq/e72QLlubuKqCTqzaQ1XuAq1K7XnuZDCA==","signingKeyID":"study-authority-test-v1"}"#
}
