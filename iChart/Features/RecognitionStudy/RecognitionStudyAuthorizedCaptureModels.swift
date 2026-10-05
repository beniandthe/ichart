import Foundation

enum RecognitionStudyAuthorizedCaptureContractError: Error, Equatable {
    case fixedValueMismatch(field: String, expected: String, actual: String)
    case integerOutsideSafeJSONDomain(field: String)
    case invalidBuildNumber(String)
    case buildBelowGrantMinimum(actual: UInt64, minimum: UInt64)
    case ticketNotInVerifiedGrant
    case clientContextDoesNotMatchVerifiedGrant
    case observedSurfaceDoesNotMatchTicket
    case captureOutsideGrantValidityWindow
    case trajectoryDoesNotMatchPacket
    case signedGrantDigestMismatch
}

/// Values in this transport contract must round-trip through JavaScript and
/// PostgreSQL without integer precision loss.
private enum RecognitionStudySafeJSONInteger {
    static let maximum: UInt64 = 9_007_199_254_740_991

    static func require(_ value: UInt64, field: String) throws {
        guard value <= maximum else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .integerOutsideSafeJSONDomain(field: field)
        }
    }

    static func require(_ value: Int64, field: String) throws {
        guard value >= 0, UInt64(value) <= maximum else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .integerOutsideSafeJSONDomain(field: field)
        }
    }

    static func canonicalBuildNumber(_ value: String) throws -> UInt64 {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              value == "0" || value.first != "0",
              let parsed = UInt64(value) else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .invalidBuildNumber(value)
        }
        try require(parsed, field: "actualBuildNumber")
        return parsed
    }
}

/// A capability produced only by successful Ed25519, validity-window,
/// bundle-identity, build-floor, and safe-integer verification. Ordinary
/// decoded grants cannot construct one.
struct RecognitionStudyVerifiedCaptureGrant: Sendable {
    let signedGrant: RecognitionStudySignedCaptureGrant
    let payload: RecognitionStudyCaptureGrantPayload
    let signedGrantSHA256: RecognitionStudySHA256
    let actualBundleIdentifier: String
    let actualBuildNumber: String

    private init(
        signedGrant: RecognitionStudySignedCaptureGrant,
        payload: RecognitionStudyCaptureGrantPayload,
        signedGrantSHA256: RecognitionStudySHA256,
        actualBundleIdentifier: String,
        actualBuildNumber: String
    ) {
        self.signedGrant = signedGrant
        self.payload = payload
        self.signedGrantSHA256 = signedGrantSHA256
        self.actualBundleIdentifier = actualBundleIdentifier
        self.actualBuildNumber = actualBuildNumber
    }

    static func verify(
        _ signedGrant: RecognitionStudySignedCaptureGrant,
        trustedPublicKeysByID: [String: Data],
        validationUnixSeconds: Int64,
        actualBundleIdentifier: String,
        actualBuildNumber: String
    ) throws -> Self {
        try RecognitionStudySafeJSONInteger.require(
            validationUnixSeconds,
            field: "validationUnixSeconds"
        )
        let payload = try signedGrant.verify(
            trustedPublicKeysByID: trustedPublicKeysByID,
            validationUnixSeconds: validationUnixSeconds
        )
        try validateSafeIntegerDomain(payload)

        let expectedBundle = payload.clientRequirements
            .expectedBundleIdentifier.rawValue
        guard actualBundleIdentifier == expectedBundle else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .fixedValueMismatch(
                    field: "actualBundleIdentifier",
                    expected: expectedBundle,
                    actual: actualBundleIdentifier
                )
        }
        let buildNumber = try RecognitionStudySafeJSONInteger
            .canonicalBuildNumber(actualBuildNumber)
        let minimum = payload.clientRequirements.minimumBuildNumber
        guard buildNumber >= minimum else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .buildBelowGrantMinimum(actual: buildNumber, minimum: minimum)
        }

        return Self(
            signedGrant: signedGrant,
            payload: payload,
            signedGrantSHA256: try signedGrant.signedArtifactSHA256(),
            actualBundleIdentifier: actualBundleIdentifier,
            actualBuildNumber: actualBuildNumber
        )
    }

    func ticket(
        captureAuthorizationID: UUID
    ) -> RecognitionStudyCaptureGrantPromptTicket? {
        let identifier = RecognitionStudyCanonicalUUID(captureAuthorizationID)
        return payload.captureTickets.first {
            $0.captureAuthorizationID == identifier
        }
    }

    func validateExactTicket(
        _ ticket: RecognitionStudyCaptureGrantPromptTicket
    ) throws {
        guard Int(ticket.ordinal) < payload.captureTickets.count,
              payload.captureTickets[Int(ticket.ordinal)] == ticket else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .ticketNotInVerifiedGrant
        }
    }

    private static func validateSafeIntegerDomain(
        _ payload: RecognitionStudyCaptureGrantPayload
    ) throws {
        try RecognitionStudySafeJSONInteger.require(
            UInt64(payload.expectedCaptureCount),
            field: "grant.expectedCaptureCount"
        )
        try RecognitionStudySafeJSONInteger.require(
            payload.authorizationEpoch,
            field: "grant.authorizationEpoch"
        )
        try RecognitionStudySafeJSONInteger.require(
            payload.consentBinding.consentLedgerEpoch,
            field: "grant.consentLedgerEpoch"
        )
        try RecognitionStudySafeJSONInteger.require(
            payload.clientRequirements.minimumBuildNumber,
            field: "grant.minimumBuildNumber"
        )
        try RecognitionStudySafeJSONInteger.require(
            payload.issuedAtUnixSeconds,
            field: "grant.issuedAtUnixSeconds"
        )
        try RecognitionStudySafeJSONInteger.require(
            payload.notBeforeUnixSeconds,
            field: "grant.notBeforeUnixSeconds"
        )
        try RecognitionStudySafeJSONInteger.require(
            payload.expiresAtUnixSeconds,
            field: "grant.expiresAtUnixSeconds"
        )
        for ticket in payload.captureTickets {
            try RecognitionStudySafeJSONInteger.require(
                UInt64(ticket.ordinal),
                field: "grant.captureTickets.ordinal"
            )
        }
    }
}

/// A raw-trajectory transport envelope for one externally authorized ticket.
///
/// Deliberately absent: prompt ID/text/kind, intended chord, writer/person or
/// account identity, consent record, dataset/split/eligibility, recognizer,
/// candidate, confidence, outcome, or any assertion of semantic truth.
struct RecognitionStudyAuthorizedCaptureEnvelope:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let currentSchemaVersion =
        "recognition-study-authorized-capture-envelope-v1"
    static let maximumCanonicalJSONByteCount = 64 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let artifactKind: RecognitionStudyArtifactKind
    let grantAuthorizationID: RecognitionStudyCanonicalUUID
    let serviceSessionID: RecognitionStudyCanonicalUUID
    let captureAuthorizationID: RecognitionStudyCanonicalUUID
    let ticketOrdinal: UInt32
    let signedGrantSHA256: RecognitionStudySHA256
    let clientAppContext: RecognitionStudyClientAppContext
    let clientObservedSurface: RecognitionStudyPresentedSurface
    let clientCapturedAtUnixMilliseconds: Int64
    let trajectoryDescriptor: RecognitionStudyTrajectoryDescriptor

    init(
        verifiedGrant: RecognitionStudyVerifiedCaptureGrant,
        ticket: RecognitionStudyCaptureGrantPromptTicket,
        clientAppContext: RecognitionStudyClientAppContext,
        clientObservedSurface: RecognitionStudyPresentedSurface,
        clientCapturedAtUnixMilliseconds: Int64,
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        artifactKind = .externallyAuthorizedTrajectoryV1
        grantAuthorizationID = verifiedGrant.payload.authorizationID
        serviceSessionID = verifiedGrant.payload.serviceSessionID
        captureAuthorizationID = ticket.captureAuthorizationID
        ticketOrdinal = ticket.ordinal
        signedGrantSHA256 = verifiedGrant.signedGrantSHA256
        self.clientAppContext = clientAppContext
        self.clientObservedSurface = clientObservedSurface
        self.clientCapturedAtUnixMilliseconds =
            clientCapturedAtUnixMilliseconds
        trajectoryDescriptor = try RecognitionStudyTrajectoryDescriptor(
            derivingFrom: packet
        )
        try validateContract()
        try validateBindings(
            verifiedGrant: verifiedGrant,
            ticket: ticket,
            packet: packet
        )
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyAuthorizedCaptureWire.Envelope.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyAuthorizedCaptureWire.Envelope
    ) throws {
        schemaVersion = wire.schemaVersion
        guard let decodedArtifactKind = RecognitionStudyArtifactKind(
            rawValue: wire.artifactKind
        ) else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .fixedValueMismatch(
                    field: "artifactKind",
                    expected: RecognitionStudyArtifactKind
                        .externallyAuthorizedTrajectoryV1.rawValue,
                    actual: wire.artifactKind
                )
        }
        artifactKind = decodedArtifactKind
        grantAuthorizationID = wire.grantAuthorizationID
        serviceSessionID = wire.serviceSessionID
        captureAuthorizationID = wire.captureAuthorizationID
        ticketOrdinal = wire.ticketOrdinal
        signedGrantSHA256 = wire.signedGrantSHA256
        clientAppContext = try Self.decodeNestedCanonicalDocument(
            wire.clientAppContext,
            as: RecognitionStudyClientAppContext.self
        )
        clientObservedSurface = try Self.decodeNestedCanonicalDocument(
            wire.clientObservedSurface,
            as: RecognitionStudyPresentedSurface.self
        )
        clientCapturedAtUnixMilliseconds =
            wire.clientCapturedAtUnixMilliseconds
        trajectoryDescriptor = try Self.decodeNestedCanonicalDocument(
            wire.trajectoryDescriptor,
            as: RecognitionStudyTrajectoryDescriptor.self
        )
        try validateContract()
    }

    func validateContract() throws {
        guard schemaVersion.rawValue == Self.currentSchemaVersion else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .fixedValueMismatch(
                    field: "schemaVersion",
                    expected: Self.currentSchemaVersion,
                    actual: schemaVersion.rawValue
                )
        }
        guard artifactKind == .externallyAuthorizedTrajectoryV1 else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .fixedValueMismatch(
                    field: "artifactKind",
                    expected: RecognitionStudyArtifactKind
                        .externallyAuthorizedTrajectoryV1.rawValue,
                    actual: artifactKind.rawValue
                )
        }
        try RecognitionStudySafeJSONInteger.require(
            UInt64(ticketOrdinal),
            field: "ticketOrdinal"
        )
        try RecognitionStudySafeJSONInteger.require(
            clientCapturedAtUnixMilliseconds,
            field: "clientCapturedAtUnixMilliseconds"
        )
        try clientAppContext.validateContract()
        try clientObservedSurface.validateContract()
        try trajectoryDescriptor.validateContract()
    }

    func validateBindings(
        verifiedGrant: RecognitionStudyVerifiedCaptureGrant,
        ticket: RecognitionStudyCaptureGrantPromptTicket,
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws {
        try validateContract()
        try verifiedGrant.validateExactTicket(ticket)
        guard signedGrantSHA256 == verifiedGrant.signedGrantSHA256 else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .signedGrantDigestMismatch
        }
        guard grantAuthorizationID == verifiedGrant.payload.authorizationID,
              serviceSessionID == verifiedGrant.payload.serviceSessionID,
              captureAuthorizationID == ticket.captureAuthorizationID,
              ticketOrdinal == ticket.ordinal else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .ticketNotInVerifiedGrant
        }
        guard clientAppContext.bundleIdentifier.rawValue
                == verifiedGrant.actualBundleIdentifier,
              clientAppContext.buildNumber.rawValue
                == verifiedGrant.actualBuildNumber else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .clientContextDoesNotMatchVerifiedGrant
        }
        guard clientObservedSurface.presentedChartStyle.rawValue
                == ticket.presentedChartStyle.rawValue,
              clientObservedSurface.clientObservedOrientation.rawValue
                == ticket.requestedOrientation.rawValue,
              clientObservedSurface.presentedPaceInstruction.rawValue
                == ticket.presentedPace.rawValue,
              clientObservedSurface.presentedSizeInstruction.rawValue
                == ticket.presentedSize.rawValue,
              clientObservedSurface.presentedConstructionInstruction.rawValue
                == ticket.presentedConstruction.rawValue else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .observedSurfaceDoesNotMatchTicket
        }
        let capturedAtUnixSeconds = clientCapturedAtUnixMilliseconds / 1_000
        guard capturedAtUnixSeconds
                >= verifiedGrant.payload.notBeforeUnixSeconds,
              capturedAtUnixSeconds
                < verifiedGrant.payload.expiresAtUnixSeconds else {
            throw RecognitionStudyAuthorizedCaptureContractError
                .captureOutsideGrantValidityWindow
        }
        do {
            try trajectoryDescriptor.validateBinding(to: packet)
        } catch {
            throw RecognitionStudyAuthorizedCaptureContractError
                .trajectoryDoesNotMatchPacket
        }
    }

    private static func decodeNestedCanonicalDocument<Wire, Document>(
        _ wire: Wire,
        as documentType: Document.Type
    ) throws -> Document
    where Wire: Encodable, Document: RecognitionStudyCanonicalJSONDocument {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try Document.decodeCanonicalData(encoder.encode(wire))
    }
}

fileprivate enum RecognitionStudyAuthorizedCaptureWire {
    struct ClientAppContext: Codable {
        let bundleIdentifier: RecognitionStudyPrintableASCII
        let appVersion: RecognitionStudyPrintableASCII
        let buildNumber: RecognitionStudyPrintableASCII
        let operatingSystemMajorVersion: UInt16
        let operatingSystemMinorVersion: UInt16
    }

    struct PresentedSurface: Codable {
        let surfaceVersion: RecognitionStudyPrintableASCII
        let presentedChartStyle: String
        let clientObservedOrientation: String
        let canvasWidth: RecognitionStudyFiniteDouble
        let canvasHeight: RecognitionStudyFiniteDouble
        let presentedPaceInstruction: String
        let presentedSizeInstruction: String
        let presentedConstructionInstruction: String
    }

    struct TrajectoryDescriptor: Codable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let packetFormatVersion: RecognitionStudyPrintableASCII
        let coordinateSpace: String
        let canonicalPacketSHA256: RecognitionStudySHA256
        let canonicalPacketByteCount: UInt64
        let strokeCount: UInt32
        let emptyStrokeCount: UInt32
        let pointCount: UInt32
        let pointTimingCoverage: String
        let creationTimingCoverage: String
        let overallTimingCoverage: String
        let containsNonFiniteTiming: Bool
    }

    struct Envelope: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let artifactKind: String
        let grantAuthorizationID: RecognitionStudyCanonicalUUID
        let serviceSessionID: RecognitionStudyCanonicalUUID
        let captureAuthorizationID: RecognitionStudyCanonicalUUID
        let ticketOrdinal: UInt32
        let signedGrantSHA256: RecognitionStudySHA256
        let clientAppContext: ClientAppContext
        let clientObservedSurface: PresentedSurface
        let clientCapturedAtUnixMilliseconds: Int64
        let trajectoryDescriptor: TrajectoryDescriptor
    }
}
