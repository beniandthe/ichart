import CryptoKit
import Foundation

enum RecognitionStudyCaptureGrantContractError: Error, Equatable {
    case fixedValueMismatch(field: String, expected: String, actual: String)
    case invalidVersion(field: String, value: String)
    case invalidPromptID(String)
    case invalidPromptKind(String)
    case invalidDisplayText
    case invalidSignatureEncoding
    case invalidTimestamp(String)
    case invalidTimestampOrder
    case invalidAuthorizationEpoch
    case invalidConsentLedgerEpoch
    case rawStrokeDonationNotAuthorized
    case invalidMinimumBuildNumber
    case emptyPromptPlan
    case promptPlanTooLarge(maximum: Int, actual: Int)
    case promptCountMismatch(expected: UInt32, actual: Int)
    case noncontiguousPromptOrdinals
    case duplicateCaptureAuthorizationID
    case duplicatePromptID
    case identifierCollision
    case untrustedSigningKey(String)
    case invalidSigningPublicKey
    case signatureVerificationFailed
    case authorizationNotYetValid
    case authorizationExpired
    case integerExceedsInteroperableJSONRange(String)
}

enum RecognitionStudyCaptureGrantPromptKind:
    String,
    Encodable,
    Hashable,
    Sendable
{
    case isolatedChord = "isolated-chord"
    case realisticRow = "realistic-row"
    case openSetNegative = "open-set-negative"
}

struct RecognitionStudyEd25519Signature: Encodable, Hashable, Sendable {
    static let byteCount = 64

    let base64Value: String

    var rawData: Data {
        // Construction and decoding both validate this exact round trip.
        Data(base64Encoded: base64Value)!
    }

    init(base64Value: String) throws {
        guard let data = Data(base64Encoded: base64Value),
              data.count == Self.byteCount,
              data.base64EncodedString() == base64Value else {
            throw RecognitionStudyCaptureGrantContractError
                .invalidSignatureEncoding
        }
        self.base64Value = base64Value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(base64Value)
    }
}

struct RecognitionStudyCaptureGrantDisplayText:
    Encodable,
    Hashable,
    Sendable
{
    static let maximumUTF8ByteCount = 256
    private static let allowedNonASCIIScalars: Set<UInt32> = [
        0x00B0, // degree / diminished
        0x00D8, // uppercase slashed O
        0x00F8, // half diminished
        0x0394, // Greek delta
        0x25B3, // white up-pointing triangle
        0x266D, // music flat
        0x266E, // music natural
        0x266F  // music sharp
    ]

    let rawValue: String

    init(canonicalString: String) throws {
        let normalized = canonicalString.precomposedStringWithCanonicalMapping
        guard !canonicalString.isEmpty,
              canonicalString.utf8.count <= Self.maximumUTF8ByteCount,
              normalized.utf8.elementsEqual(canonicalString.utf8),
              canonicalString.unicodeScalars.allSatisfy({ scalar in
                  (0x20...0x7E).contains(scalar.value)
                      || Self.allowedNonASCIIScalars.contains(scalar.value)
              }) else {
            throw RecognitionStudyCaptureGrantContractError
                .invalidDisplayText
        }
        rawValue = canonicalString
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct RecognitionStudyCaptureGrantClientRequirements:
    Encodable,
    Hashable,
    Sendable
{
    static let expectedStudyBundleIdentifier = "com.ichart.recognitionstudy"
    static let currentCaptureContractVersion =
        "recognition-study-authorized-capture-v1"

    let expectedBundleIdentifier: RecognitionStudyPrintableASCII
    let minimumBuildNumber: UInt64
    let captureContractVersion: RecognitionStudyPrintableASCII

    fileprivate init(wire: RecognitionStudyCaptureGrantWire.ClientRequirements) {
        expectedBundleIdentifier = wire.expectedBundleIdentifier
        minimumBuildNumber = wire.minimumBuildNumber
        captureContractVersion = wire.captureContractVersion
    }

    func validateContract() throws {
        try requireFixed(
            expectedBundleIdentifier,
            expected: Self.expectedStudyBundleIdentifier,
            field: "clientRequirements.expectedBundleIdentifier"
        )
        guard minimumBuildNumber > 0 else {
            throw RecognitionStudyCaptureGrantContractError
                .invalidMinimumBuildNumber
        }
        try requireInteroperableJSONInteger(
            minimumBuildNumber,
            field: "clientRequirements.minimumBuildNumber"
        )
        try requireFixed(
            captureContractVersion,
            expected: Self.currentCaptureContractVersion,
            field: "clientRequirements.captureContractVersion"
        )
    }
}

struct RecognitionStudyCaptureGrantConsentBinding:
    Encodable,
    Hashable,
    Sendable
{
    static let currentSchemaVersion = "recognition-study-consent-binding-v1"
    static let requiredScope = "chord-recognition-research-v1"

    let schemaVersion: RecognitionStudyPrintableASCII
    let consentRecordID: RecognitionStudyCanonicalUUID
    let consentRecordSHA256: RecognitionStudySHA256
    let scope: RecognitionStudyPrintableASCII
    let consentLedgerVersion: RecognitionStudyPrintableASCII
    let consentLedgerEpoch: UInt64
    let consentTextVersion: RecognitionStudyPrintableASCII
    let privacyNoticeVersion: RecognitionStudyPrintableASCII
    let dataUsePolicyVersion: RecognitionStudyPrintableASCII
    let retentionPolicyVersion: RecognitionStudyPrintableASCII
    let rawStrokeDonationAuthorized: Bool

    fileprivate init(wire: RecognitionStudyCaptureGrantWire.ConsentBinding) {
        schemaVersion = wire.schemaVersion
        consentRecordID = wire.consentRecordID
        consentRecordSHA256 = wire.consentRecordSHA256
        scope = wire.scope
        consentLedgerVersion = wire.consentLedgerVersion
        consentLedgerEpoch = wire.consentLedgerEpoch
        consentTextVersion = wire.consentTextVersion
        privacyNoticeVersion = wire.privacyNoticeVersion
        dataUsePolicyVersion = wire.dataUsePolicyVersion
        retentionPolicyVersion = wire.retentionPolicyVersion
        rawStrokeDonationAuthorized = wire.rawStrokeDonationAuthorized
    }

    func validateContract() throws {
        try requireFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "consentBinding.schemaVersion"
        )
        try requireFixed(
            scope,
            expected: Self.requiredScope,
            field: "consentBinding.scope"
        )
        guard consentLedgerEpoch > 0 else {
            throw RecognitionStudyCaptureGrantContractError
                .invalidConsentLedgerEpoch
        }
        try requireInteroperableJSONInteger(
            consentLedgerEpoch,
            field: "consentBinding.consentLedgerEpoch"
        )
        try requireVersion(
            consentLedgerVersion,
            field: "consentBinding.consentLedgerVersion"
        )
        try requireVersion(
            consentTextVersion,
            field: "consentBinding.consentTextVersion"
        )
        try requireVersion(
            privacyNoticeVersion,
            field: "consentBinding.privacyNoticeVersion"
        )
        try requireVersion(
            dataUsePolicyVersion,
            field: "consentBinding.dataUsePolicyVersion"
        )
        try requireVersion(
            retentionPolicyVersion,
            field: "consentBinding.retentionPolicyVersion"
        )
        guard rawStrokeDonationAuthorized else {
            throw RecognitionStudyCaptureGrantContractError
                .rawStrokeDonationNotAuthorized
        }
    }
}

struct RecognitionStudyCaptureGrantPromptTicket:
    Encodable,
    Hashable,
    Sendable
{
    let captureAuthorizationID: RecognitionStudyCanonicalUUID
    let ordinal: UInt32
    let promptID: RecognitionStudyPrintableASCII
    let promptKind: RecognitionStudyCaptureGrantPromptKind
    let displayText: RecognitionStudyCaptureGrantDisplayText
    let presentedChartStyle: RecognitionStudyPrintableASCII
    let requestedOrientation: RecognitionStudyPrintableASCII
    let presentedPace: RecognitionStudyPrintableASCII
    let presentedSize: RecognitionStudyPrintableASCII
    let presentedConstruction: RecognitionStudyPrintableASCII

    fileprivate init(
        wire: RecognitionStudyCaptureGrantWire.PromptTicket
    ) throws {
        captureAuthorizationID = wire.captureAuthorizationID
        ordinal = wire.ordinal
        promptID = wire.promptID
        guard let decodedPromptKind = RecognitionStudyCaptureGrantPromptKind(
            rawValue: wire.promptKind
        ) else {
            throw RecognitionStudyCaptureGrantContractError
                .invalidPromptKind(wire.promptKind)
        }
        promptKind = decodedPromptKind
        displayText = try RecognitionStudyCaptureGrantDisplayText(
            canonicalString: wire.displayText
        )
        presentedChartStyle = wire.presentedChartStyle
        requestedOrientation = wire.requestedOrientation
        presentedPace = wire.presentedPace
        presentedSize = wire.presentedSize
        presentedConstruction = wire.presentedConstruction
    }

    func validateContract() throws {
        try promptID.require(maximumUTF8ByteCount: 64)
        guard isLowercaseSlug(promptID.rawValue) else {
            throw RecognitionStudyCaptureGrantContractError
                .invalidPromptID(promptID.rawValue)
        }
        try requireOneOf(
            presentedChartStyle,
            choices: ["simple-chord-sheet", "rhythm-section-sheet"],
            field: "captureTickets.presentedChartStyle"
        )
        try requireOneOf(
            requestedOrientation,
            choices: ["portrait", "landscape"],
            field: "captureTickets.requestedOrientation"
        )
        try requireOneOf(
            presentedPace,
            choices: ["natural", "fast", "careful"],
            field: "captureTickets.presentedPace"
        )
        try requireOneOf(
            presentedSize,
            choices: ["small", "normal", "large"],
            field: "captureTickets.presentedSize"
        )
        try requireOneOf(
            presentedConstruction,
            choices: ["root-first", "modifier-first", "mixed-or-retraced"],
            field: "captureTickets.presentedConstruction"
        )
    }
}

/// Service-authored instructions for one complete, externally authorized
/// writer-independent capture session. This payload deliberately contains no
/// writer identity, linkage HMAC, cohort role, ground truth, or eligibility.
struct RecognitionStudyCaptureGrantPayload:
    RecognitionStudyCanonicalJSONDocument,
    Hashable,
    Sendable
{
    static let currentSchemaVersion = "recognition-study-capture-grant-v1"
    static let currentArtifactKind = "externally-authorized-session-grant-v1"
    static let currentCollectionProtocolVersion =
        "writer-independent-capture-v2"
    static let maximumPromptCount = 256
    static let maximumCanonicalJSONByteCount = 256 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let artifactKind: RecognitionStudyPrintableASCII
    let authorizationID: RecognitionStudyCanonicalUUID
    let serviceSessionID: RecognitionStudyCanonicalUUID
    let datasetVersion: RecognitionStudyPrintableASCII
    let collectionProtocolVersion: RecognitionStudyPrintableASCII
    let promptPlanVersion: RecognitionStudyPrintableASCII
    let expectedCaptureCount: UInt32
    let consentBinding: RecognitionStudyCaptureGrantConsentBinding
    let clientRequirements: RecognitionStudyCaptureGrantClientRequirements
    let captureTickets: [RecognitionStudyCaptureGrantPromptTicket]
    let issuedAtUnixSeconds: Int64
    let notBeforeUnixSeconds: Int64
    let expiresAtUnixSeconds: Int64
    let authorizationEpoch: UInt64

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureGrantWire.Payload.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(wire: RecognitionStudyCaptureGrantWire.Payload) throws {
        schemaVersion = wire.schemaVersion
        artifactKind = wire.artifactKind
        authorizationID = wire.authorizationID
        serviceSessionID = wire.serviceSessionID
        datasetVersion = wire.datasetVersion
        collectionProtocolVersion = wire.collectionProtocolVersion
        promptPlanVersion = wire.promptPlanVersion
        expectedCaptureCount = wire.expectedCaptureCount
        consentBinding = RecognitionStudyCaptureGrantConsentBinding(
            wire: wire.consentBinding
        )
        clientRequirements = RecognitionStudyCaptureGrantClientRequirements(
            wire: wire.clientRequirements
        )
        captureTickets = try wire.captureTickets.map(
            RecognitionStudyCaptureGrantPromptTicket.init(wire:)
        )
        issuedAtUnixSeconds = wire.issuedAtUnixSeconds
        notBeforeUnixSeconds = wire.notBeforeUnixSeconds
        expiresAtUnixSeconds = wire.expiresAtUnixSeconds
        authorizationEpoch = wire.authorizationEpoch
    }

    func validateContract() throws {
        try requireFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "payload.schemaVersion"
        )
        try requireFixed(
            artifactKind,
            expected: Self.currentArtifactKind,
            field: "payload.artifactKind"
        )
        try requireFixed(
            collectionProtocolVersion,
            expected: Self.currentCollectionProtocolVersion,
            field: "payload.collectionProtocolVersion"
        )
        try requireVersion(datasetVersion, field: "payload.datasetVersion")
        try requireVersion(
            promptPlanVersion,
            field: "payload.promptPlanVersion"
        )
        try consentBinding.validateContract()
        try clientRequirements.validateContract()

        guard authorizationEpoch > 0 else {
            throw RecognitionStudyCaptureGrantContractError
                .invalidAuthorizationEpoch
        }
        try requireInteroperableJSONInteger(
            authorizationEpoch,
            field: "authorizationEpoch"
        )
        for (value, field) in [
            (issuedAtUnixSeconds, "issuedAtUnixSeconds"),
            (notBeforeUnixSeconds, "notBeforeUnixSeconds"),
            (expiresAtUnixSeconds, "expiresAtUnixSeconds")
        ] where value < 0 {
            throw RecognitionStudyCaptureGrantContractError
                .invalidTimestamp(field)
        }
        for (value, field) in [
            (issuedAtUnixSeconds, "issuedAtUnixSeconds"),
            (notBeforeUnixSeconds, "notBeforeUnixSeconds"),
            (expiresAtUnixSeconds, "expiresAtUnixSeconds")
        ] {
            try requireInteroperableJSONInteger(value, field: field)
        }
        guard issuedAtUnixSeconds <= notBeforeUnixSeconds,
              notBeforeUnixSeconds < expiresAtUnixSeconds else {
            throw RecognitionStudyCaptureGrantContractError
                .invalidTimestampOrder
        }

        guard !captureTickets.isEmpty else {
            throw RecognitionStudyCaptureGrantContractError.emptyPromptPlan
        }
        guard captureTickets.count <= Self.maximumPromptCount else {
            throw RecognitionStudyCaptureGrantContractError.promptPlanTooLarge(
                maximum: Self.maximumPromptCount,
                actual: captureTickets.count
            )
        }
        guard UInt64(expectedCaptureCount) == UInt64(captureTickets.count) else {
            throw RecognitionStudyCaptureGrantContractError.promptCountMismatch(
                expected: expectedCaptureCount,
                actual: captureTickets.count
            )
        }

        for ticket in captureTickets {
            try ticket.validateContract()
        }
        guard captureTickets.enumerated().allSatisfy({ index, ticket in
            ticket.ordinal == UInt32(index)
        }) else {
            throw RecognitionStudyCaptureGrantContractError
                .noncontiguousPromptOrdinals
        }
        guard Set(captureTickets.map(\.captureAuthorizationID)).count
                == captureTickets.count else {
            throw RecognitionStudyCaptureGrantContractError
                .duplicateCaptureAuthorizationID
        }
        guard Set(captureTickets.map { $0.promptID.rawValue }).count
                == captureTickets.count else {
            throw RecognitionStudyCaptureGrantContractError.duplicatePromptID
        }

        var allIdentifiers = Set<String>()
        allIdentifiers.insert(authorizationID.rawValue)
        allIdentifiers.insert(serviceSessionID.rawValue)
        for ticket in captureTickets {
            allIdentifiers.insert(ticket.captureAuthorizationID.rawValue)
        }
        guard allIdentifiers.count == captureTickets.count + 2 else {
            throw RecognitionStudyCaptureGrantContractError.identifierCollision
        }
    }
}

/// An Ed25519-authenticated service artifact. Verification covers the exact
/// canonical payload bytes. The full canonical wrapper digest is the value a
/// later capture envelope must bind as `authorityArtifactSHA256`.
struct RecognitionStudySignedCaptureGrant:
    RecognitionStudyCanonicalJSONDocument,
    Hashable,
    Sendable
{
    static let currentSchemaVersion =
        "recognition-study-signed-capture-grant-v1"
    static let maximumCanonicalJSONByteCount = 272 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let payload: RecognitionStudyCaptureGrantPayload
    let signingKeyID: RecognitionStudyPrintableASCII
    let signatureBase64: RecognitionStudyEd25519Signature

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureGrantWire.SignedGrant.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyCaptureGrantWire.SignedGrant
    ) throws {
        schemaVersion = wire.schemaVersion
        payload = try RecognitionStudyCaptureGrantPayload(wire: wire.payload)
        signingKeyID = wire.signingKeyID
        signatureBase64 = try RecognitionStudyEd25519Signature(
            base64Value: wire.signatureBase64
        )
    }

    func validateContract() throws {
        try requireFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "schemaVersion"
        )
        try signingKeyID.require(maximumUTF8ByteCount: 64)
        try payload.validateContract()
    }

    func signedArtifactSHA256() throws -> RecognitionStudySHA256 {
        RecognitionStudySHA256(digesting: try canonicalData())
    }

    /// Verifies service authority and the grant's fixed validity window. The
    /// keyring is injected so production code can pin an allowlisted key ID;
    /// this contract file does not contain service keys or enable capture.
    @discardableResult
    func verify(
        trustedPublicKeysByID: [String: Data],
        validationUnixSeconds: Int64
    ) throws -> RecognitionStudyCaptureGrantPayload {
        try validateContract()
        guard let rawPublicKey = trustedPublicKeysByID[signingKeyID.rawValue]
        else {
            throw RecognitionStudyCaptureGrantContractError
                .untrustedSigningKey(signingKeyID.rawValue)
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: rawPublicKey
            )
        } catch {
            throw RecognitionStudyCaptureGrantContractError
                .invalidSigningPublicKey
        }
        let payloadData = try payload.canonicalData()
        guard publicKey.isValidSignature(
            signatureBase64.rawData,
            for: payloadData
        ) else {
            throw RecognitionStudyCaptureGrantContractError
                .signatureVerificationFailed
        }
        guard validationUnixSeconds >= payload.notBeforeUnixSeconds else {
            throw RecognitionStudyCaptureGrantContractError
                .authorizationNotYetValid
        }
        guard validationUnixSeconds < payload.expiresAtUnixSeconds else {
            throw RecognitionStudyCaptureGrantContractError.authorizationExpired
        }
        return payload
    }
}

fileprivate enum RecognitionStudyCaptureGrantWire {
    struct ClientRequirements: Decodable {
        let expectedBundleIdentifier: RecognitionStudyPrintableASCII
        let minimumBuildNumber: UInt64
        let captureContractVersion: RecognitionStudyPrintableASCII
    }

    struct ConsentBinding: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let consentRecordID: RecognitionStudyCanonicalUUID
        let consentRecordSHA256: RecognitionStudySHA256
        let scope: RecognitionStudyPrintableASCII
        let consentLedgerVersion: RecognitionStudyPrintableASCII
        let consentLedgerEpoch: UInt64
        let consentTextVersion: RecognitionStudyPrintableASCII
        let privacyNoticeVersion: RecognitionStudyPrintableASCII
        let dataUsePolicyVersion: RecognitionStudyPrintableASCII
        let retentionPolicyVersion: RecognitionStudyPrintableASCII
        let rawStrokeDonationAuthorized: Bool
    }

    struct PromptTicket: Decodable {
        let captureAuthorizationID: RecognitionStudyCanonicalUUID
        let ordinal: UInt32
        let promptID: RecognitionStudyPrintableASCII
        let promptKind: String
        let displayText: String
        let presentedChartStyle: RecognitionStudyPrintableASCII
        let requestedOrientation: RecognitionStudyPrintableASCII
        let presentedPace: RecognitionStudyPrintableASCII
        let presentedSize: RecognitionStudyPrintableASCII
        let presentedConstruction: RecognitionStudyPrintableASCII
    }

    struct Payload: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let artifactKind: RecognitionStudyPrintableASCII
        let authorizationID: RecognitionStudyCanonicalUUID
        let serviceSessionID: RecognitionStudyCanonicalUUID
        let datasetVersion: RecognitionStudyPrintableASCII
        let collectionProtocolVersion: RecognitionStudyPrintableASCII
        let promptPlanVersion: RecognitionStudyPrintableASCII
        let expectedCaptureCount: UInt32
        let consentBinding: ConsentBinding
        let clientRequirements: ClientRequirements
        let captureTickets: [PromptTicket]
        let issuedAtUnixSeconds: Int64
        let notBeforeUnixSeconds: Int64
        let expiresAtUnixSeconds: Int64
        let authorizationEpoch: UInt64
    }

    struct SignedGrant: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let payload: Payload
        let signingKeyID: RecognitionStudyPrintableASCII
        let signatureBase64: String
    }
}

private func requireFixed(
    _ value: RecognitionStudyPrintableASCII,
    expected: String,
    field: String
) throws {
    guard value.rawValue == expected else {
        throw RecognitionStudyCaptureGrantContractError.fixedValueMismatch(
            field: field,
            expected: expected,
            actual: value.rawValue
        )
    }
}

private let maximumInteroperableJSONInteger: UInt64 = 9_007_199_254_740_991

private func requireInteroperableJSONInteger(
    _ value: UInt64,
    field: String
) throws {
    guard value <= maximumInteroperableJSONInteger else {
        throw RecognitionStudyCaptureGrantContractError
            .integerExceedsInteroperableJSONRange(field)
    }
}

private func requireInteroperableJSONInteger(
    _ value: Int64,
    field: String
) throws {
    guard value >= 0,
          UInt64(value) <= maximumInteroperableJSONInteger else {
        throw RecognitionStudyCaptureGrantContractError
            .integerExceedsInteroperableJSONRange(field)
    }
}

private func requireOneOf(
    _ value: RecognitionStudyPrintableASCII,
    choices: Set<String>,
    field: String
) throws {
    guard choices.contains(value.rawValue) else {
        throw RecognitionStudyCaptureGrantContractError.fixedValueMismatch(
            field: field,
            expected: choices.sorted().joined(separator: "|"),
            actual: value.rawValue
        )
    }
}

private func requireVersion(
    _ value: RecognitionStudyPrintableASCII,
    field: String
) throws {
    let scalars = value.rawValue.unicodeScalars
    let firstIsAlphanumeric = scalars.first.map { scalar in
        (48...57).contains(scalar.value) || (97...122).contains(scalar.value)
    } ?? false
    let allAreVersionCharacters = scalars.allSatisfy { scalar in
        (48...57).contains(scalar.value)
            || (97...122).contains(scalar.value)
            || scalar.value == 45
            || scalar.value == 46
            || scalar.value == 95
    }
    guard firstIsAlphanumeric, allAreVersionCharacters else {
        throw RecognitionStudyCaptureGrantContractError.invalidVersion(
            field: field,
            value: value.rawValue
        )
    }
}

private func isLowercaseSlug(_ value: String) -> Bool {
    let components = value.split(separator: "-", omittingEmptySubsequences: false)
    guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else {
        return false
    }
    return components.allSatisfy { component in
        component.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (97...122).contains(scalar.value)
        }
    }
}
