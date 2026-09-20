import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyCaptureContractTests: XCTestCase {
    func testCanonicalValueGoldenBytesUseExactLowercaseRepresentations() throws {
        let fixture = CanonicalValueFixture(
            ascii: try RecognitionStudyPrintableASCII("a/b"),
            digest: try RecognitionStudySHA256(
                canonicalString: String(repeating: "ab", count: 32)
            ),
            finite: try RecognitionStudyFiniteDouble(
                Double(bitPattern: 0x8000_0000_0000_0000)
            ),
            uuid: try RecognitionStudyCanonicalUUID(
                canonicalString: "aabbccdd-eeff-0011-2233-445566778899"
            )
        )

        let expected = #"{"ascii":"a/b","digest":"abababababababababababababababababababababababababababababababab","finite":"8000000000000000","uuid":"aabbccdd-eeff-0011-2233-445566778899"}"#
        let data = try fixture.canonicalData()

        XCTAssertEqual(String(decoding: data, as: UTF8.self), expected)
        XCTAssertEqual(
            try CanonicalValueFixture.decodeCanonicalData(data),
            fixture
        )
    }

    func testCanonicalDecodeRejectsUppercaseWhitespaceUnknownKeysAndNull() throws {
        let fixture = CanonicalValueFixture(
            ascii: try RecognitionStudyPrintableASCII("a/b"),
            digest: try RecognitionStudySHA256(
                canonicalString: String(repeating: "ab", count: 32)
            ),
            finite: try RecognitionStudyFiniteDouble(-0.0),
            uuid: try RecognitionStudyCanonicalUUID(
                canonicalString: "aabbccdd-eeff-0011-2233-445566778899"
            )
        )
        let canonical = String(decoding: try fixture.canonicalData(), as: UTF8.self)

        let uppercaseUUID = canonical.replacingOccurrences(
            of: "aabbccdd-eeff-0011-2233-445566778899",
            with: "AABBCCDD-EEFF-0011-2233-445566778899"
        )
        XCTAssertThrowsError(
            try CanonicalValueFixture.decodeCanonicalData(data(uppercaseUUID))
        )

        let uppercaseDigest = canonical.replacingOccurrences(
            of: String(repeating: "ab", count: 32),
            with: String(repeating: "AB", count: 32)
        )
        XCTAssertThrowsError(
            try CanonicalValueFixture.decodeCanonicalData(data(uppercaseDigest))
        )

        let finiteWithHexLetters = try CanonicalValueFixture(
            ascii: fixture.ascii,
            digest: fixture.digest,
            finite: RecognitionStudyFiniteDouble(1.5),
            uuid: fixture.uuid
        ).canonicalData()
        let uppercaseFinite = String(
            decoding: finiteWithHexLetters,
            as: UTF8.self
        ).replacingOccurrences(
            of: "3ff8000000000000",
            with: "3FF8000000000000"
        )
        XCTAssertThrowsError(
            try CanonicalValueFixture.decodeCanonicalData(data(uppercaseFinite))
        )

        XCTAssertThrowsError(
            try CanonicalValueFixture.decodeCanonicalData(data(" \(canonical)"))
        )

        let unknownKey = String(canonical.dropLast()) + ",\"unknown\":\"x\"}"
        XCTAssertThrowsError(
            try CanonicalValueFixture.decodeCanonicalData(data(unknownKey))
        )

        let explicitNull = canonical.replacingOccurrences(
            of: "\"ascii\":\"a/b\"",
            with: "\"ascii\":null"
        )
        XCTAssertThrowsError(
            try CanonicalValueFixture.decodeCanonicalData(data(explicitNull))
        )
    }

    func testCanonicalValuesRejectUnicodeOverflowAndNonfiniteDoubles() throws {
        XCTAssertThrowsError(try RecognitionStudyPrintableASCII("café"))
        XCTAssertThrowsError(
            try RecognitionStudyPrintableASCII(
                String(
                    repeating: "a",
                    count: RecognitionStudyPrintableASCII
                        .absoluteMaximumUTF8ByteCount + 1
                )
            )
        )
        XCTAssertThrowsError(try RecognitionStudyFiniteDouble(.infinity))
        XCTAssertThrowsError(try RecognitionStudyFiniteDouble(.nan))

        let infinityFixture = #"{"ascii":"ok","digest":"abababababababababababababababababababababababababababababababab","finite":"7ff0000000000000","uuid":"aabbccdd-eeff-0011-2233-445566778899"}"#
        XCTAssertThrowsError(
            try CanonicalValueFixture.decodeCanonicalData(data(infinityFixture))
        )
    }

    func testAllDocumentDecodersRejectOversizeBeforeParsingInvalidJSON() {
        let demonstrablyInvalidJSON = oversizedInvalidJSON(
            maximumByteCount: RecognitionStudyCaptureLimits
                .maximumAuthorizationBindingV1CanonicalJSONByteCount
        )
        XCTAssertThrowsError(
            try JSONSerialization.jsonObject(with: demonstrablyInvalidJSON)
        )

        assertOversizedCanonicalJSONRejectedBeforeParsing(
            RecognitionStudyAuthorizationBinding.self,
            expectedMaximumByteCount: RecognitionStudyCaptureLimits
                .maximumAuthorizationBindingV1CanonicalJSONByteCount
        )
        assertOversizedCanonicalJSONRejectedBeforeParsing(
            RecognitionStudyClientAppContext.self,
            expectedMaximumByteCount: RecognitionStudyCaptureLimits
                .maximumClientAppContextV1CanonicalJSONByteCount
        )
        assertOversizedCanonicalJSONRejectedBeforeParsing(
            RecognitionStudySessionManifest.self,
            expectedMaximumByteCount: RecognitionStudyCaptureLimits
                .maximumSessionManifestV1CanonicalJSONByteCount
        )
        assertOversizedCanonicalJSONRejectedBeforeParsing(
            RecognitionStudyPresentedSurface.self,
            expectedMaximumByteCount: RecognitionStudyCaptureLimits
                .maximumPresentedSurfaceV1CanonicalJSONByteCount
        )
        assertOversizedCanonicalJSONRejectedBeforeParsing(
            RecognitionStudyTrajectoryDescriptor.self,
            expectedMaximumByteCount: RecognitionStudyCaptureLimits
                .maximumTrajectoryDescriptorV1CanonicalJSONByteCount
        )
        assertOversizedCanonicalJSONRejectedBeforeParsing(
            RecognitionStudyCaptureEnvelope.self,
            expectedMaximumByteCount: RecognitionStudyCaptureLimits
                .maximumCaptureEnvelopeV1CanonicalJSONByteCount
        )
    }

    func testAuthorizationBindingEnforcesCrossFieldRulesAndKeepsExternalReserved() throws {
        let authorizationID = uuid("10101010-2020-3030-4040-505050505050")
        let local = try RecognitionStudyAuthorizationBinding
            .localEngineeringDryRun(authorizationID: authorizationID)
        let localText = String(decoding: try local.canonicalData(), as: UTF8.self)
        let localObject = try jsonObject(try local.canonicalData())

        XCTAssertTrue(local.isSupportedForCapture)
        XCTAssertEqual(
            Set(localObject.keys),
            ["authorizationID", "kind", "schemaVersion"]
        )

        let authorityDigest = try RecognitionStudySHA256(
            canonicalString: String(repeating: "cd", count: 32)
        )
        let external = try RecognitionStudyAuthorizationBinding
            .reservedExternalOneUse(
                authorizationID: authorizationID,
                authorityArtifactSHA256: authorityDigest
            )
        let externalText = String(
            decoding: try external.canonicalData(),
            as: UTF8.self
        )

        XCTAssertFalse(external.isSupportedForCapture)
        XCTAssertEqual(
            try RecognitionStudyAuthorizationBinding.decodeCanonicalData(
                try external.canonicalData()
            ),
            external
        )

        let localWithAuthority = externalText.replacingOccurrences(
            of: RecognitionStudyAuthorizationKind.externalOneUseV1.rawValue,
            with: RecognitionStudyAuthorizationKind.localEngineeringDryRunV1.rawValue
        )
        XCTAssertThrowsError(
            try RecognitionStudyAuthorizationBinding.decodeCanonicalData(
                data(localWithAuthority)
            )
        )

        let externalWithoutAuthority = localText.replacingOccurrences(
            of: RecognitionStudyAuthorizationKind.localEngineeringDryRunV1.rawValue,
            with: RecognitionStudyAuthorizationKind.externalOneUseV1.rawValue
        )
        XCTAssertThrowsError(
            try RecognitionStudyAuthorizationBinding.decodeCanonicalData(
                data(externalWithoutAuthority)
            )
        )

        let explicitNull = localText.replacingOccurrences(
            of: "\"kind\":",
            with: "\"authorityArtifactSHA256\":null,\"kind\":"
        )
        XCTAssertThrowsError(
            try RecognitionStudyAuthorizationBinding.decodeCanonicalData(
                data(explicitNull)
            )
        )
    }

    func testSessionAndClientContextAreStrictlyBoundedAndNonidentifying() throws {
        let contract = try sampleContract()
        let sessionData = try contract.session.canonicalData()
        let sessionObject = try jsonObject(sessionData)
        let appContext = try XCTUnwrap(
            sessionObject["clientAppContext"] as? [String: Any]
        )

        XCTAssertEqual(
            Set(sessionObject.keys),
            [
                "artifactKind",
                "clientAppContext",
                "clientCreatedAtUnixMilliseconds",
                "collectionProtocolVersion",
                "limitsVersion",
                "localSessionID",
                "schemaVersion"
            ]
        )
        XCTAssertEqual(
            Set(appContext.keys),
            [
                "appVersion",
                "buildNumber",
                "bundleIdentifier",
                "operatingSystemMajorVersion",
                "operatingSystemMinorVersion"
            ]
        )
        XCTAssertEqual(
            appContext["bundleIdentifier"] as? String,
            RecognitionStudyClientAppContext.expectedBundleIdentifier
        )
        XCTAssertEqual(
            try RecognitionStudySessionManifest.decodeCanonicalData(sessionData),
            contract.session
        )

        let keys = recursiveJSONKeys(sessionObject).map { $0.lowercased() }
        for forbidden in ["deviceid", "account", "installation", "participant"] {
            XCTAssertFalse(
                keys.contains { $0.contains(forbidden) },
                "Session contract unexpectedly contains \(forbidden)."
            )
        }
    }

    func testPresentedSurfaceSeparatesInstructionsFromObservedOrientation() throws {
        let surface = try RecognitionStudyPresentedSurface(
            presentedChartStyle: .rhythmSectionSheet,
            clientObservedOrientation: .landscape,
            canvasWidth: 1024,
            canvasHeight: 768,
            presentedPaceInstruction: .fast,
            presentedSizeInstruction: .small,
            presentedConstructionInstruction: .modifierFirst
        )
        let object = try jsonObject(try surface.canonicalData())

        XCTAssertEqual(
            Set(object.keys),
            [
                "canvasHeight",
                "canvasWidth",
                "clientObservedOrientation",
                "presentedChartStyle",
                "presentedConstructionInstruction",
                "presentedPaceInstruction",
                "presentedSizeInstruction",
                "surfaceVersion"
            ]
        )
        XCTAssertEqual(object["clientObservedOrientation"] as? String, "landscape")
        XCTAssertEqual(object["presentedPaceInstruction"] as? String, "fast")
        XCTAssertNil(object["observedPace"])
        XCTAssertNil(object["actualPace"])
        XCTAssertNil(object["actualConstruction"])

        XCTAssertThrowsError(
            try RecognitionStudyPresentedSurface(
                presentedChartStyle: .simpleChordSheet,
                clientObservedOrientation: .portrait,
                canvasWidth: .infinity,
                canvasHeight: 768,
                presentedPaceInstruction: .natural,
                presentedSizeInstruction: .normal,
                presentedConstructionInstruction: .rootFirst
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyPresentedSurface(
                presentedChartStyle: .simpleChordSheet,
                clientObservedOrientation: .portrait,
                canvasWidth: 0,
                canvasHeight: 768,
                presentedPaceInstruction: .natural,
                presentedSizeInstruction: .normal,
                presentedConstructionInstruction: .rootFirst
            )
        )
    }

    func testTrajectoryDescriptorIsDerivedAndPacketBound() throws {
        let packet = try samplePacket(x: 1)
        let descriptor = try RecognitionStudyTrajectoryDescriptor(
            derivingFrom: packet
        )
        let canonicalPacketData = try packet.canonicalData()

        XCTAssertEqual(
            descriptor.canonicalPacketSHA256,
            RecognitionStudySHA256(digesting: canonicalPacketData)
        )
        XCTAssertEqual(
            descriptor.canonicalPacketByteCount,
            UInt64(canonicalPacketData.count)
        )
        XCTAssertEqual(descriptor.strokeCount, 1)
        XCTAssertEqual(descriptor.emptyStrokeCount, 0)
        XCTAssertEqual(descriptor.pointCount, 1)
        XCTAssertNoThrow(try descriptor.validateBinding(to: packet))
        XCTAssertThrowsError(
            try descriptor.validateBinding(to: samplePacket(x: 2))
        )
        XCTAssertThrowsError(
            try RecognitionStudyTrajectoryDescriptor(
                derivingFrom: ChordInkCanonicalTrajectoryPacket(strokes: [])
            )
        )

        XCTAssertNoThrow(
            try RecognitionStudyCaptureLimits
                .validateCanonicalPacketByteCountBeforeDecoding(
                    RecognitionStudyCaptureLimits.maximumCanonicalPacketByteCount
                )
        )
        XCTAssertThrowsError(
            try RecognitionStudyCaptureLimits
                .validateCanonicalPacketByteCountBeforeDecoding(
                    RecognitionStudyCaptureLimits.maximumCanonicalPacketByteCount + 1
                )
        )

        let oversizedStroke = InkStroke(
            points: (0...Int(RecognitionStudyCaptureLimits.maximumPointCountPerStroke))
                .map { index in
                    InkPoint(x: Double(index), y: 1, timeOffset: nil)
                }
        )
        XCTAssertThrowsError(
            try RecognitionStudyTrajectoryDescriptor(
                derivingFrom: ChordInkCanonicalTrajectoryPacket(
                    strokes: [oversizedStroke]
                )
            )
        )
    }

    func testEnvelopeHasExactMechanicalKeysAndNoSemanticOrIdentityFields() throws {
        let contract = try sampleContract()
        let envelopeData = try contract.envelope.canonicalData()
        let object = try jsonObject(envelopeData)

        XCTAssertEqual(
            Set(object.keys),
            [
                "artifactKind",
                "authorizationBinding",
                "captureOrdinal",
                "clientCapturedAtUnixMilliseconds",
                "collectionProtocolVersion",
                "localCaptureID",
                "localSessionID",
                "presentedSurface",
                "schemaVersion",
                "sessionManifestSHA256",
                "trajectoryDescriptor"
            ]
        )
        XCTAssertEqual(
            try RecognitionStudyCaptureEnvelope.decodeCanonicalData(envelopeData),
            contract.envelope
        )
        XCTAssertNoThrow(
            try contract.envelope.validateBindings(
                to: contract.session,
                packet: contract.packet
            )
        )

        let allKeys = recursiveJSONKeys(object).map { $0.lowercased() }
        for forbidden in [
            "prompt", "chord", "label", "writer", "person", "handedness",
            "split", "consent", "eligibility", "leakage", "candidate",
            "confidence", "trust", "raw", "drawing"
        ] {
            XCTAssertFalse(
                allKeys.contains { $0.contains(forbidden) },
                "Capture envelope unexpectedly contains \(forbidden)."
            )
        }

        let canonical = String(decoding: envelopeData, as: UTF8.self)
        let unknownKey = String(canonical.dropLast()) + ",\"prompt\":\"C7\"}"
        XCTAssertThrowsError(
            try RecognitionStudyCaptureEnvelope.decodeCanonicalData(
                data(unknownKey)
            )
        )
    }

    func testEnvelopeRejectsReservedExternalAuthorizationAndOrdinalOverflow() throws {
        let contract = try sampleContract()
        let external = try RecognitionStudyAuthorizationBinding
            .reservedExternalOneUse(
                authorizationID: uuid("90909090-8080-7070-6060-505050505050"),
                authorityArtifactSHA256: try RecognitionStudySHA256(
                    canonicalString: String(repeating: "ef", count: 32)
                )
            )

        XCTAssertThrowsError(
            try RecognitionStudyCaptureEnvelope(
                localCaptureID: uuid("11111111-2222-3333-4444-555555555555"),
                captureOrdinal: 0,
                authorizationBinding: external,
                sessionManifest: contract.session,
                clientCapturedAtUnixMilliseconds: 1_700_000_000_001,
                presentedSurface: contract.surface,
                trajectoryDescriptor: contract.descriptor
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureContractError,
                .unsupportedAuthorizationKind(.externalOneUseV1)
            )
        }

        XCTAssertThrowsError(
            try RecognitionStudyCaptureEnvelope(
                localCaptureID: uuid("11111111-2222-3333-4444-555555555555"),
                captureOrdinal: RecognitionStudyCaptureLimits
                    .maximumCapturesPerSession,
                authorizationBinding: contract.authorization,
                sessionManifest: contract.session,
                clientCapturedAtUnixMilliseconds: 1_700_000_000_001,
                presentedSurface: contract.surface,
                trajectoryDescriptor: contract.descriptor
            )
        )
    }

    func testStrictEnvelopeDecodeRejectsIndependentCrossFieldInvalidWires() throws {
        let contract = try sampleContract()
        let validEnvelope = try jsonObject(contract.envelope.canonicalData())

        var reservedExternalEnvelope = validEnvelope
        var reservedExternalAuthorization = try XCTUnwrap(
            reservedExternalEnvelope["authorizationBinding"] as? [String: Any]
        )
        reservedExternalAuthorization["kind"] =
            RecognitionStudyAuthorizationKind.externalOneUseV1.rawValue
        reservedExternalAuthorization["authorityArtifactSHA256"] =
            String(repeating: "ef", count: 32)
        reservedExternalEnvelope["authorizationBinding"] =
            reservedExternalAuthorization

        XCTAssertThrowsError(
            try RecognitionStudyCaptureEnvelope.decodeCanonicalData(
                canonicalJSONData(reservedExternalEnvelope)
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureContractError,
                .unsupportedAuthorizationKind(.externalOneUseV1)
            )
        }

        var localWithAuthorityEnvelope = validEnvelope
        var localWithAuthority = try XCTUnwrap(
            localWithAuthorityEnvelope["authorizationBinding"] as? [String: Any]
        )
        localWithAuthority["authorityArtifactSHA256"] =
            String(repeating: "cd", count: 32)
        localWithAuthorityEnvelope["authorizationBinding"] = localWithAuthority

        XCTAssertThrowsError(
            try RecognitionStudyCaptureEnvelope.decodeCanonicalData(
                canonicalJSONData(localWithAuthorityEnvelope)
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureContractError,
                .localAuthorizationMustNotHaveAuthorityArtifact
            )
        }

        var impossibleDescriptorEnvelope = validEnvelope
        var impossibleDescriptor = try XCTUnwrap(
            impossibleDescriptorEnvelope["trajectoryDescriptor"] as? [String: Any]
        )
        impossibleDescriptor["strokeCount"] = 1
        impossibleDescriptor["emptyStrokeCount"] = 2
        impossibleDescriptorEnvelope["trajectoryDescriptor"] = impossibleDescriptor

        XCTAssertThrowsError(
            try RecognitionStudyCaptureEnvelope.decodeCanonicalData(
                canonicalJSONData(impossibleDescriptorEnvelope)
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureContractError,
                .invariantViolation(
                    "emptyStrokeCount must not exceed strokeCount"
                )
            )
        }
    }

    private func sampleContract() throws -> (
        session: RecognitionStudySessionManifest,
        surface: RecognitionStudyPresentedSurface,
        packet: ChordInkCanonicalTrajectoryPacket,
        descriptor: RecognitionStudyTrajectoryDescriptor,
        authorization: RecognitionStudyAuthorizationBinding,
        envelope: RecognitionStudyCaptureEnvelope
    ) {
        let appContext = try RecognitionStudyClientAppContext(
            appVersion: "1.0",
            buildNumber: "100",
            operatingSystemMajorVersion: 26,
            operatingSystemMinorVersion: 0
        )
        let session = try RecognitionStudySessionManifest(
            localSessionID: uuid("01010101-0202-0303-0404-050505050505"),
            clientCreatedAtUnixMilliseconds: 1_700_000_000_000,
            clientAppContext: appContext
        )
        let surface = try RecognitionStudyPresentedSurface(
            presentedChartStyle: .simpleChordSheet,
            clientObservedOrientation: .portrait,
            canvasWidth: 768,
            canvasHeight: 1024,
            presentedPaceInstruction: .natural,
            presentedSizeInstruction: .normal,
            presentedConstructionInstruction: .rootFirst
        )
        let packet = try samplePacket(x: 1)
        let descriptor = try RecognitionStudyTrajectoryDescriptor(
            derivingFrom: packet
        )
        let authorization = try RecognitionStudyAuthorizationBinding
            .localEngineeringDryRun(
                authorizationID: uuid("06060606-0707-0808-0909-101010101010")
            )
        let envelope = try RecognitionStudyCaptureEnvelope(
            localCaptureID: uuid("11111111-1212-1313-1414-151515151515"),
            captureOrdinal: 0,
            authorizationBinding: authorization,
            sessionManifest: session,
            clientCapturedAtUnixMilliseconds: 1_700_000_000_001,
            presentedSurface: surface,
            trajectoryDescriptor: descriptor
        )
        return (
            session,
            surface,
            packet,
            descriptor,
            authorization,
            envelope
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

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func canonicalJSONData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func assertOversizedCanonicalJSONRejectedBeforeParsing<Document>(
        _: Document.Type,
        expectedMaximumByteCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where Document: RecognitionStudyCanonicalJSONDocument {
        XCTAssertEqual(
            Document.maximumCanonicalJSONByteCount,
            expectedMaximumByteCount,
            file: file,
            line: line
        )
        let invalidJSON = oversizedInvalidJSON(
            maximumByteCount: expectedMaximumByteCount
        )
        XCTAssertThrowsError(
            try Document.decodeCanonicalData(invalidJSON),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCanonicalValueError,
                .canonicalJSONTooLarge(
                    maximumByteCount: expectedMaximumByteCount,
                    actualByteCount: expectedMaximumByteCount + 1
                ),
                file: file,
                line: line
            )
        }
    }

    private func oversizedInvalidJSON(maximumByteCount: Int) -> Data {
        Data(repeating: 0xff, count: maximumByteCount + 1)
    }

    private func recursiveJSONKeys(_ value: Any) -> [String] {
        if let object = value as? [String: Any] {
            return object.keys.flatMap { key in
                [key] + recursiveJSONKeys(object[key] as Any)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(recursiveJSONKeys)
        }
        return []
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func data(_ value: String) -> Data {
        Data(value.utf8)
    }
}

private struct CanonicalValueFixture:
    RecognitionStudyCanonicalJSONDocument,
    Equatable
{
    static let maximumCanonicalJSONByteCount = 8 * 1024

    let ascii: RecognitionStudyPrintableASCII
    let digest: RecognitionStudySHA256
    let finite: RecognitionStudyFiniteDouble
    let uuid: RecognitionStudyCanonicalUUID

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: CanonicalValueFixtureWire.self,
            construct: {
                Self(
                    ascii: $0.ascii,
                    digest: $0.digest,
                    finite: $0.finite,
                    uuid: $0.uuid
                )
            }
        )
    }

    func validateContract() throws {}
}

private struct CanonicalValueFixtureWire: Decodable {
    let ascii: RecognitionStudyPrintableASCII
    let digest: RecognitionStudySHA256
    let finite: RecognitionStudyFiniteDouble
    let uuid: RecognitionStudyCanonicalUUID
}
