import Foundation

enum RecognitionStudyCaptureTransportContractError: Error, Equatable {
    case fixedValueMismatch(field: String, expected: String, actual: String)
    case uploadBodyTooLarge(maximum: Int, actual: Int)
    case invalidCanonicalUploadRequest
    case uploadRequestDoesNotMatchArtifacts
    case signedGrantDigestMismatch
    case receiptDoesNotMatchCapture
    case invalidReceiptState
    case integerOutsideSafeJSONDomain(field: String)
}

struct RecognitionStudyCaptureGrantRequest: Encodable, Sendable {
    static let currentSchemaVersion =
        "recognition-study-capture-grant-request-v1"
    static let maximumCanonicalJSONByteCount = 1_024

    let schemaVersion: RecognitionStudyPrintableASCII
    let clientRequestID: RecognitionStudyCanonicalUUID

    init(clientRequestID: UUID) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        self.clientRequestID = RecognitionStudyCanonicalUUID(clientRequestID)
    }

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumCanonicalJSONByteCount else {
            throw RecognitionStudyCaptureTransportContractError
                .uploadBodyTooLarge(
                    maximum: Self.maximumCanonicalJSONByteCount,
                    actual: data.count
                )
        }
        return data
    }
}

/// One exact upload body. Prompt content remains only in the signed authority
/// artifact; neither the external envelope nor the raw packet gains label,
/// writer, recognizer, candidate, outcome, split, or eligibility authority.
struct RecognitionStudyCaptureUploadRequest: Encodable, Sendable {
    static let currentSchemaVersion =
        "recognition-study-capture-upload-request-v1"
    static let maximumCanonicalJSONByteCount = 6 * 1024 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let signedGrant: RecognitionStudySignedCaptureGrant
    let envelope: RecognitionStudyAuthorizedCaptureEnvelope
    let canonicalPacketBase64: String

    init(
        verifiedGrant: RecognitionStudyVerifiedCaptureGrant,
        ticket: RecognitionStudyCaptureGrantPromptTicket,
        envelope: RecognitionStudyAuthorizedCaptureEnvelope,
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws {
        try verifiedGrant.validateExactTicket(ticket)
        try envelope.validateBindings(
            verifiedGrant: verifiedGrant,
            ticket: ticket,
            packet: packet
        )
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        signedGrant = verifiedGrant.signedGrant
        self.envelope = envelope
        canonicalPacketBase64 = try packet.canonicalData()
            .base64EncodedString()
    }

    func canonicalData() throws -> Data {
        guard schemaVersion.rawValue == Self.currentSchemaVersion else {
            throw RecognitionStudyCaptureTransportContractError
                .fixedValueMismatch(
                    field: "schemaVersion",
                    expected: Self.currentSchemaVersion,
                    actual: schemaVersion.rawValue
                )
        }
        guard let packetData = Data(base64Encoded: canonicalPacketBase64),
              packetData.base64EncodedString() == canonicalPacketBase64 else {
            throw RecognitionStudyCaptureTransportContractError
                .fixedValueMismatch(
                    field: "canonicalPacketBase64",
                    expected: "canonical base64",
                    actual: "invalid"
                )
        }
        try RecognitionStudyCaptureLimits
            .validateCanonicalPacketByteCountBeforeDecoding(packetData.count)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumCanonicalJSONByteCount else {
            throw RecognitionStudyCaptureTransportContractError
                .uploadBodyTooLarge(
                    maximum: Self.maximumCanonicalJSONByteCount,
                    actual: data.count
                )
        }
        return data
    }
}

/// An immutable upload body together with the two canonical artifacts needed
/// to validate a receipt after a crash or an indeterminate network response.
///
/// Construction requires a live verified grant. Restoration does not extend
/// or recreate authority: it accepts only the exact canonical request bytes,
/// proves that their signed-grant, envelope, and packet bindings still match,
/// and leaves signature/current-consent enforcement to the server. Access
/// tokens are deliberately absent so credentials can never enter the queue.
struct RecognitionStudyPreparedCaptureUpload: Equatable, Sendable {
    let canonicalRequestBody: Data
    let envelope: RecognitionStudyAuthorizedCaptureEnvelope
    let packet: ChordInkCanonicalTrajectoryPacket

    var captureAuthorizationID: RecognitionStudyCanonicalUUID {
        envelope.captureAuthorizationID
    }

    init(
        verifiedGrant: RecognitionStudyVerifiedCaptureGrant,
        ticket: RecognitionStudyCaptureGrantPromptTicket,
        envelope: RecognitionStudyAuthorizedCaptureEnvelope,
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws {
        let requestBody = try RecognitionStudyCaptureUploadRequest(
            verifiedGrant: verifiedGrant,
            ticket: ticket,
            envelope: envelope,
            packet: packet
        ).canonicalData()
        try self.init(
            restoringCanonicalRequestBody: requestBody,
            canonicalEnvelopeData: envelope.canonicalData(),
            canonicalPacketData: packet.canonicalData()
        )
    }

    init(
        restoringCanonicalRequestBody requestBody: Data,
        canonicalEnvelopeData envelopeData: Data,
        canonicalPacketData packetData: Data
    ) throws {
        guard requestBody.count
                <= RecognitionStudyCaptureUploadRequest
                    .maximumCanonicalJSONByteCount else {
            throw RecognitionStudyCaptureTransportContractError
                .uploadBodyTooLarge(
                    maximum: RecognitionStudyCaptureUploadRequest
                        .maximumCanonicalJSONByteCount,
                    actual: requestBody.count
                )
        }
        try RecognitionStudyCaptureLimits
            .validateCanonicalPacketByteCountBeforeDecoding(packetData.count)

        let envelope = try RecognitionStudyAuthorizedCaptureEnvelope
            .decodeCanonicalData(envelopeData)
        let packet = try ChordInkCanonicalTrajectoryPacket
            .decodeCanonicalData(packetData)
        let requestObject: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(
                with: requestBody
            ) as? [String: Any] else {
                throw RecognitionStudyCaptureTransportContractError
                    .invalidCanonicalUploadRequest
            }
            requestObject = object
        } catch let error as RecognitionStudyCaptureTransportContractError {
            throw error
        } catch {
            throw RecognitionStudyCaptureTransportContractError
                .invalidCanonicalUploadRequest
        }

        let exactKeys = Set([
            "canonicalPacketBase64",
            "envelope",
            "schemaVersion",
            "signedGrant"
        ])
        guard Set(requestObject.keys) == exactKeys,
              requestObject["schemaVersion"] as? String
                == RecognitionStudyCaptureUploadRequest.currentSchemaVersion,
              let signedGrantObject = requestObject["signedGrant"]
                as? [String: Any],
              let requestEnvelopeObject = requestObject["envelope"]
                as? [String: Any],
              let packetBase64 = requestObject["canonicalPacketBase64"]
                as? String,
              let decodedPacket = Data(base64Encoded: packetBase64),
              decodedPacket.base64EncodedString() == packetBase64,
              decodedPacket == packetData else {
            throw RecognitionStudyCaptureTransportContractError
                .uploadRequestDoesNotMatchArtifacts
        }

        let canonicalRequestData = try Self.canonicalJSONData(requestObject)
        let signedGrantData = try Self.canonicalJSONData(signedGrantObject)
        let requestEnvelopeData = try Self.canonicalJSONData(
            requestEnvelopeObject
        )
        guard canonicalRequestData == requestBody,
              requestEnvelopeData == envelopeData else {
            throw RecognitionStudyCaptureTransportContractError
                .invalidCanonicalUploadRequest
        }

        let signedGrant = try RecognitionStudySignedCaptureGrant
            .decodeCanonicalData(signedGrantData)
        try Self.validateStructuralBindings(
            signedGrant: signedGrant,
            envelope: envelope,
            packet: packet
        )

        canonicalRequestBody = requestBody
        self.envelope = envelope
        self.packet = packet
    }

    private static func canonicalJSONData(_ value: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(value) else {
            throw RecognitionStudyCaptureTransportContractError
                .invalidCanonicalUploadRequest
        }
        do {
            return try JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw RecognitionStudyCaptureTransportContractError
                .invalidCanonicalUploadRequest
        }
    }

    /// Structural restoration only. This cannot mint a verified grant and is
    /// not a substitute for the server's signature, owner, consent, and
    /// one-use-ticket checks.
    private static func validateStructuralBindings(
        signedGrant: RecognitionStudySignedCaptureGrant,
        envelope: RecognitionStudyAuthorizedCaptureEnvelope,
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws {
        try signedGrant.validateContract()
        try envelope.validateContract()
        let payload = signedGrant.payload
        guard envelope.signedGrantSHA256
                == RecognitionStudySHA256(
                    digesting: try signedGrant.canonicalData()
                ) else {
            throw RecognitionStudyCaptureTransportContractError
                .signedGrantDigestMismatch
        }
        guard envelope.grantAuthorizationID == payload.authorizationID,
              envelope.serviceSessionID == payload.serviceSessionID,
              Int(envelope.ticketOrdinal) < payload.captureTickets.count else {
            throw RecognitionStudyCaptureTransportContractError
                .uploadRequestDoesNotMatchArtifacts
        }
        let ticket = payload.captureTickets[Int(envelope.ticketOrdinal)]
        guard ticket.ordinal == envelope.ticketOrdinal,
              ticket.captureAuthorizationID
                == envelope.captureAuthorizationID,
              envelope.clientAppContext.bundleIdentifier
                == payload.clientRequirements.expectedBundleIdentifier,
              envelope.clientObservedSurface.presentedChartStyle.rawValue
                == ticket.presentedChartStyle.rawValue,
              envelope.clientObservedSurface.clientObservedOrientation.rawValue
                == ticket.requestedOrientation.rawValue,
              envelope.clientObservedSurface
                .presentedPaceInstruction.rawValue
                == ticket.presentedPace.rawValue,
              envelope.clientObservedSurface
                .presentedSizeInstruction.rawValue
                == ticket.presentedSize.rawValue,
              envelope.clientObservedSurface
                .presentedConstructionInstruction.rawValue
                == ticket.presentedConstruction.rawValue else {
            throw RecognitionStudyCaptureTransportContractError
                .uploadRequestDoesNotMatchArtifacts
        }
        let capturedAtUnixSeconds =
            envelope.clientCapturedAtUnixMilliseconds / 1_000
        guard capturedAtUnixSeconds >= payload.notBeforeUnixSeconds,
              capturedAtUnixSeconds < payload.expiresAtUnixSeconds else {
            throw RecognitionStudyCaptureTransportContractError
                .uploadRequestDoesNotMatchArtifacts
        }
        do {
            try envelope.trajectoryDescriptor.validateBinding(to: packet)
        } catch {
            throw RecognitionStudyCaptureTransportContractError
                .uploadRequestDoesNotMatchArtifacts
        }
    }
}

struct RecognitionStudyCaptureReceipt:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let currentSchemaVersion =
        "recognition-study-capture-receipt-v1"
    static let maximumCanonicalJSONByteCount = 8 * 1024
    private static let maximumSafeJSONInteger: Int64 = 9_007_199_254_740_991

    let schemaVersion: RecognitionStudyPrintableASCII
    let accepted: Bool
    let receiptID: RecognitionStudyCanonicalUUID
    let captureAuthorizationID: RecognitionStudyCanonicalUUID
    let envelopeSHA256: RecognitionStudySHA256
    let canonicalPacketSHA256: RecognitionStudySHA256
    let canonicalPacketByteCount: UInt64
    let receivedAtUnixMilliseconds: Int64
    let replayed: Bool
    let grantCompleted: Bool

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureTransportWire.Receipt.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyCaptureTransportWire.Receipt
    ) throws {
        schemaVersion = wire.schemaVersion
        accepted = wire.accepted
        receiptID = wire.receiptID
        captureAuthorizationID = wire.captureAuthorizationID
        envelopeSHA256 = wire.envelopeSHA256
        canonicalPacketSHA256 = wire.canonicalPacketSHA256
        canonicalPacketByteCount = wire.canonicalPacketByteCount
        receivedAtUnixMilliseconds = wire.receivedAtUnixMilliseconds
        replayed = wire.replayed
        grantCompleted = wire.grantCompleted
        try validateContract()
    }

    func validateContract() throws {
        guard schemaVersion.rawValue == Self.currentSchemaVersion else {
            throw RecognitionStudyCaptureTransportContractError
                .fixedValueMismatch(
                    field: "schemaVersion",
                    expected: Self.currentSchemaVersion,
                    actual: schemaVersion.rawValue
                )
        }
        guard accepted else {
            throw RecognitionStudyCaptureTransportContractError
                .invalidReceiptState
        }
        guard canonicalPacketByteCount > 0,
              canonicalPacketByteCount <= UInt64(
                  RecognitionStudyCaptureLimits.maximumCanonicalPacketByteCount
              ),
              canonicalPacketByteCount <= UInt64(Self.maximumSafeJSONInteger)
        else {
            throw RecognitionStudyCaptureTransportContractError
                .integerOutsideSafeJSONDomain(
                    field: "canonicalPacketByteCount"
                )
        }
        guard receivedAtUnixMilliseconds >= 0,
              receivedAtUnixMilliseconds <= Self.maximumSafeJSONInteger else {
            throw RecognitionStudyCaptureTransportContractError
                .integerOutsideSafeJSONDomain(
                    field: "receivedAtUnixMilliseconds"
                )
        }
    }

    func validateBinding(
        envelope: RecognitionStudyAuthorizedCaptureEnvelope,
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws {
        try validateContract()
        let envelopeDigest = RecognitionStudySHA256(
            digesting: try envelope.canonicalData()
        )
        let packetData = try packet.canonicalData()
        let packetDigest = RecognitionStudySHA256(digesting: packetData)
        guard captureAuthorizationID == envelope.captureAuthorizationID,
              envelopeSHA256 == envelopeDigest,
              canonicalPacketSHA256 == packetDigest,
              canonicalPacketByteCount == UInt64(packetData.count) else {
            throw RecognitionStudyCaptureTransportContractError
                .receiptDoesNotMatchCapture
        }
    }
}

fileprivate enum RecognitionStudyCaptureTransportWire {
    struct Receipt: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let accepted: Bool
        let receiptID: RecognitionStudyCanonicalUUID
        let captureAuthorizationID: RecognitionStudyCanonicalUUID
        let envelopeSHA256: RecognitionStudySHA256
        let canonicalPacketSHA256: RecognitionStudySHA256
        let canonicalPacketByteCount: UInt64
        let receivedAtUnixMilliseconds: Int64
        let replayed: Bool
        let grantCompleted: Bool
    }
}
